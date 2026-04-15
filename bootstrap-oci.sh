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

wait_for_resource() {
  local namespace="$1"
  local resource_type="$2"
  local resource_name="$3"
  local condition="$4"
  local timeout="${5:-10m}"
  local deadline=$(($(date +%s) + $(timeout_to_seconds "${timeout}")))
  local message
  local dots=0
  local dot_states=("" "." ".." "...")

  if [[ "${condition}" == "exists" ]]; then
    message="Waiting for ${resource_type}/${resource_name} to exist in namespace ${namespace}"
  else
    message="Waiting for ${resource_type}/${resource_name} ${condition} in namespace ${namespace}"
  fi

  printf "%s" "${message}"

  while true; do
    if [[ "${condition}" == "exists" ]]; then
      if kubectl get "${resource_type}" "${resource_name}" -n "${namespace}" >/dev/null 2>&1; then
        printf "\n"
        return 0
      fi
    else
      if kubectl wait --for="${condition}" "${resource_type}/${resource_name}" -n "${namespace}" --timeout=5s >/dev/null 2>&1; then
        printf "\n"
        return 0
      fi
    fi

    if (( $(date +%s) >= deadline )); then
      printf "\n"
      return 1
    fi

    dots=$(( (dots + 1) % 4 ))
    printf "\r%s%s" "${message}" "${dot_states[dots]}"
    sleep 5
  done
}

wait_for_deployment_available() {
  wait_for_resource "${1}" "deployment" "${2}" "condition=Available" "${3:-10m}"
}

wait_for_helmrepository_exists() {
  wait_for_resource "${1}" "helmrepository" "${2}" "exists" "${3:-10m}"
}

wait_for_helmrelease_exists() {
  wait_for_resource "${1}" "helmrelease" "${2}" "exists" "${3:-10m}"
}

suspend_helmreleases() {
  local namespace="${1}"
  shift
  local release_names=("${@}")

  for release_name in "${release_names[@]}"; do
    wait_for_helmrelease_exists "${namespace}" "${release_name}" "10m"
    flux suspend hr "${release_name}" -n "${namespace}"
  done
}

wait_for_helmrelease() {
  wait_for_resource "${1}" "helmrelease" "${2}" "condition=Ready" "${3:-5m}"
}

resume_helmreleases() {
  local namespace="${1}"
  shift
  local release_names=("${@}")

  for release_name in "${release_names[@]}"; do
    flux resume hr "${release_name}" -n "${namespace}"
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

run_oci_publish_pipeline() {
  local namespace="${1}"

  local manifest_path=$(get_oci_pipelinerun_manifest_path)

  set_oci_pipelinerun_params "${manifest_path}"

  echo "Applying Helm chart OCI publish PipelineRun manifest: ${manifest_path}"
  local pipelinerun_name=$(kubectl create -f "${manifest_path}" -o jsonpath='{.metadata.name}')
  echo "Triggered PipelineRun ${pipelinerun_name}"

  wait_for_pipelinerun_success "${namespace}" "${pipelinerun_name}" "1h"

  rm "${manifest_path}"
}

run_oci_publish_flow() {
  local namespace="infra"
  local addons=(artifactory-oss-snapshot-cleanup artifactory-oss-trash-cleanup)

  suspend_helmreleases "${namespace}" "${addons[@]}"
  wait_for_deployment_available "${namespace}" "artifactory-jcr" "15m"
  run_oci_publish_pipeline "${namespace}"
  wait_for_helmrepository_exists "${namespace}" "artifactory-oci" "10m"
  resume_helmreleases "${namespace}" "${addons[@]}"
}

run_oci_publish_flow
