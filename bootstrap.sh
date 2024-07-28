#!/bin/bash

set -eu

yes_or_no() {  
  select response in "Yes" "No"; do
    case "${response}" in
        Yes ) echo "${response}"; break;;
        No ) exit;;
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
    printf "The '%s' environment variable points to the '%s' file. \nDo you what to use the later file for the deployment?\n" "SOPS_AGE_KEY_FILE" "${sops_age_key_file}"
    local response=$(yes_or_no)
    if [ "${response}" == "Yes" ]; then
      create_namespace "${namespace}"

      local sops_age_private_key=$(get_sops_age_private_key "${sops_age_key_file}")

      create_age_key_secret "${namespace}" "sops-age" "${sops_age_private_key}"
    fi
  fi
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
repository="rainbow-infra-engine"
branch="${branch}"

sops_age_key_file=$(echo "${SOPS_AGE_KEY_FILE:-}" | xargs)

create_sops_age_secret "${sops_age_namespace}" "${sops_age_key_file}"
bootstrap_flux "${namespace}" "${owner}" "${repository}" "${branch}" "${cluster}"