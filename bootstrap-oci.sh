script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Convert a duration string into seconds.
timeout_to_seconds() {
  local timeout="${1}"

  if [[ "${timeout}" =~ ^([0-9]+)s$ ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "${timeout}" =~ ^([0-9]+)m$ ]]; then
    echo "$((${BASH_REMATCH[1]} * 60))"
  elif [[ "${timeout}" =~ ^([0-9]+)h$ ]]; then
    echo "$((${BASH_REMATCH[1]} * 3600))"
  elif [[ "${timeout}" =~ ^[0-9]+$ ]]; then
    echo "${timeout}"
  else
    echo "600"
  fi
}

wait_for_deployment_available() {
  local namespace="${1}"
  local selector="${2}"
  local timeout="${3:-10m}"
  local timeout_seconds=$(timeout_to_seconds "${timeout}")
  local deadline=$((${SECONDS} + ${timeout_seconds}))

  while true; do
    if kubectl get deployment -l "${selector}" -n "${namespace}" >/dev/null 2>&1; then
      echo "Found deployment matching selector '${selector}' in namespace ${namespace}, waiting for availability..."
      if kubectl wait --for=condition=available deployment -l "${selector}" -n "${namespace}" --timeout=5s >/dev/null 2>&1; then
        echo "Deployment matching selector '${selector}' is available"
        return 0
      fi
    else
      echo "Waiting for deployment resource matching selector '${selector}' to appear in namespace ${namespace}..."
    fi

    if (( ${SECONDS} >= ${deadline} )); then
      echo "Timed out waiting for deployment matching selector '${selector}' in namespace ${namespace}" >&2
      return 1
    fi

    sleep 5
  done
}

get_oci_pipelinerun_manifest_path() {
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local manifest_path="${script_dir}/pipelineruns/helm-chart-oci-publish.yaml"

  if [[ ! -f "${manifest_path}" ]]; then
    echo "PipelineRun manifest not found: ${manifest_path}" >&2
    return 1
  fi

  local tmp_file=$(mktemp)
  cp "${manifest_path}" "${tmp_file}"

  echo "${tmp_file}"
}

set_oci_pipelinerun_params() {
  local manifest_path="${1}"

  local helm_repo_json=$(kubectl get helmrepository artifactory-oci -n infra -o json 2>/dev/null || echo "{}")
  local insecure_status=$(echo "${helm_repo_json}" | yq '.spec.insecure // "false"' -o=json | tr -d '"')
  local helm_registry_url=$(echo "${helm_repo_json}" | yq '.spec.url // ""' -o=json | tr -d '"')
  local skip_tls="false"
  local lower_insecure_status=$(echo "${insecure_status}" | tr '[:upper:]' '[:lower:]')

  if [[ "${lower_insecure_status}" == "true" ]]; then
    skip_tls="true"
  fi

  printf "Setting skipTls to %s based on artifactory-oci HelmRepository insecure status: %s in manifest %s\n" "${skip_tls}" "${insecure_status:-<missing>}" "${manifest_path}"
  yq -i "(.spec.params[] | select(.name == \"skipTls\")).value = \"${skip_tls}\"" "${manifest_path}"

  if [[ -n "${helm_registry_url}" ]]; then
    printf "Setting helm-registry to %s based on artifactory-oci HelmRepository URL: %s in manifest %s\n" "${helm_registry_url}" "${helm_registry_url}" "${manifest_path}"
    yq -i "(.spec.params[] | select(.name == \"helm-registry\")).value = \"${helm_registry_url}\"" "${manifest_path}"
  fi
}

wait_for_pipelinerun_success() {
  local namespace="${1}"
  local pipelinerun_name="${2}"
  local timeout="${3:-1h}"

  echo "Waiting for PipelineRun ${pipelinerun_name} to succeed in namespace ${namespace}..."
  if kubectl wait --for=condition=Succeeded pipelinerun/"${pipelinerun_name}" -n "${namespace}" --timeout="${timeout}"; then
    echo "PipelineRun ${pipelinerun_name} succeeded"
    return 0
  fi

  echo "PipelineRun ${pipelinerun_name} failed or timed out" >&2
  kubectl describe pipelinerun "${pipelinerun_name}" -n "${namespace}" || true
  return 1
}

wait_for_helmrepository_ready() {
  local namespace="${1}"
  local repository_name="${2}"
  local timeout="${3:-10m}"

  echo "Waiting for HelmRepository ${repository_name} to become Ready in namespace ${namespace}..."
  if kubectl wait --for=condition=Ready helmrepository/"${repository_name}" -n "${namespace}" --timeout="${timeout}"; then
    echo "HelmRepository ${repository_name} is Ready"
    return 0
  fi

  echo "HelmRepository ${repository_name} did not become Ready" >&2
  kubectl describe helmrepository/"${repository_name}" -n "${namespace}" || true
  return 1
}

wait_for_helmrelease() {
  local namespace="${1}"
  local release_name="${2}"
  local timeout="${3:-5m}"
  local deadline=$(($(date +%s) + $(timeout_to_seconds "${timeout}")))

  while true; do
    if kubectl get helmrelease "${release_name}" -n "${namespace}" >/dev/null 2>&1; then
      return 0
    fi

    if (( $(date +%s) >= deadline )); then
      echo "Timed out waiting for HelmRelease ${release_name} to exist in namespace ${namespace}" >&2
      return 1
    fi

    sleep 5
  done
}

unsuspend_helmreleases() {
  local namespace="${1}"
  shift
  local release_names=("${@}")

  for release_name in "${release_names[@]}"; do
    wait_for_helmrelease "${namespace}" "${release_name}" "10m"
    echo "Unsuspending HelmRelease ${release_name} in namespace ${namespace}"
    kubectl patch helmrelease "${release_name}" -n "${namespace}" --type merge -p '{"spec":{"suspend":false}}'
  done
}

run_oci_pipelinerun_flow() {
  local manifest_path=$(get_oci_pipelinerun_manifest_path)

  set_oci_pipelinerun_params "${manifest_path}"

  echo "Applying Helm chart OCI publish PipelineRun manifest: ${manifest_path}"
  local pipelinerun_name=$(kubectl create -f "${manifest_path}" -o jsonpath='{.metadata.name}')
  echo "Triggered PipelineRun ${pipelinerun_name}"

  wait_for_pipelinerun_success "infra" "${pipelinerun_name}" "1h"
  wait_for_helmrepository_ready "infra" "artifactory-oci" "10m"
  unsuspend_helmreleases "infra" artifactory-oss-snapshot-cleanup artifactory-oss-trash-cleanup

  rm "${manifest_path}"
}

wait_for_deployment_available "infra" "app.kubernetes.io/instance=artifactory-jcr" "15m"
run_oci_pipelinerun_flow
