#!/bin/bash

set -eu

yes_or_no() {
  local question="$1"

  while true; do
    read -p "${question} [y/n] " response
    case "${response}" in
      [yY] ) echo yes;
        break;;
      [nN] ) echo no;
        exit;;
    esac
  done
}

get_sops_age_private_key() {
  local sops_age_key_file="$1"

  local regex='#\spublic\skey:\s.\+'

  echo $(grep -e "${regex}" "${sops_age_key_file}" -A 1 | grep -v -e "${regex}")
}

create_namespace() {
  local namespace="$1"

  local result=$(kubectl get namespaces | tail -n +2 | awk '{print $1}' | grep "${namespace}")

  if [ "${result}" != "${namespace}" ]; then
      kubectl create namespace "${namespace}"
  fi
}

create_age_key_secret() {
  local namespace="$1"
  local secret_name="$2"
  local sops_age_private_key="$3"

  local result=$(kubectl get secrets --namespace="${namespace}" | tail -n +2 | awk '{print $1}' | grep "${secret_name}")

  if [ "${result}" != "${secret_name}" ]; then
    kubectl create secret generic "${secret_name}" --namespace="${namespace}" --from-literal=identity.agekey="${sops_age_private_key}"
  fi
}

create_sops_age_secret() {
  local namespace="$1"
  local sops_age_key_file="$2"

  if [ -f "${sops_age_key_file}" ]; then
    local question=$(printf "The '%s' environment variable points to the '%s' file. \nDo you want to use the later file for the deployment?\n" "SOPS_AGE_KEY_FILE" "${sops_age_key_file}")
    local response=$(yes_or_no "${question}")
    if [ "${response}" == "yes" ]; then
      create_namespace "${namespace}"

      local sops_age_private_key=$(get_sops_age_private_key "${sops_age_key_file}")

      create_age_key_secret "${namespace}" "sops-age" "${sops_age_private_key}"
    fi
  fi
}

timeout_to_seconds() {
  local timeout="$1"

  if [[ "${timeout}" =~ ^([0-9]+)s$ ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "${timeout}" =~ ^([0-9]+)m$ ]]; then
    echo "$((BASH_REMATCH[1] * 60))"
  elif [[ "${timeout}" =~ ^([0-9]+)h$ ]]; then
    echo "$((BASH_REMATCH[1] * 3600))"
  elif [[ "${timeout}" =~ ^[0-9]+$ ]]; then
    echo "${timeout}"
  else
    echo "600"
  fi
}

wait_for_deployment_available() {
  local namespace="$1"
  local selector="$2"
  local timeout="${3:-10m}"
  local timeout_seconds=$(timeout_to_seconds "${timeout}")
  local deadline=$((SECONDS + timeout_seconds))

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

    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for deployment matching selector '${selector}' in namespace ${namespace}" >&2
      return 1
    fi

    sleep 5
  done
}

start_helm_chart_oci_publish() {
  local namespace="$1"
  local repository="$2"
  local helm_charts_dir="${3:-addons}"
  local helm_registry="${4:-oci://artifactory-jcr.infra.svc.cluster.local:8082/docker-local}"

  if ! command -v tkn >/dev/null 2>&1; then
    echo "tkn CLI not found; skipping helm-chart-oci-publish pipeline start."
    return
  fi

  echo "Starting helm-chart-oci-publish pipeline..."
  tkn pipeline start helm-chart-oci-publish -n "${namespace}" \
    --param namespace="${namespace}" \
    --param repository="${repository}" \
    --param helm-charts-dir="${helm_charts_dir}" \
    --param helm-registry="${helm_registry}"
}

bootstrap_flux() {
  local namespace="$1"
  local owner="$2"
  local repository="$3"
  local branch="$4"
  local cluster="$5"

  flux bootstrap github \
    --namespace="${namespace}" \
    --components-extra=image-reflector-controller,image-automation-controller \
    --token-auth \
    --owner="${owner}" \
    --repository="${repository}" \
    --branch="${branch}" \
    --path=clusters/"${cluster}" \
    --personal
}

cluster="${1}"
branch="${2}"

namespace="flux-system"
sops_age_namespace="infra"
owner="biya-bi"
repository="nguiland-infra-engine"
branch="${branch}"

sops_age_key_file=$(echo "${SOPS_AGE_KEY_FILE:-}" | xargs)

create_sops_age_secret "${sops_age_namespace}" "${sops_age_key_file}"
bootstrap_flux "${namespace}" "${owner}" "${repository}" "${branch}" "${cluster}"

wait_for_deployment_available "infra" "app.kubernetes.io/instance=artifactory-jcr" "15m"
start_helm_chart_oci_publish "infra" "helm-addons" "addons" "oci://artifactory-jcr.infra.svc.cluster.local:8082/docker-local"