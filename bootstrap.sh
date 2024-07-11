#!/bin/bash

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

create_sops_age_secret() {
  local namespace="$1"
  local sops_age_key_file="$2"

  if [ -f "${sops_age_key_file}" ]; then
    printf "The '%s' environment variable points to the '%s' file. Do you what to use the later file for the deployment?\n" "SOPS_AGE_KEY_FILE" "${sops_age_key_file}"
    local response=$(yes_or_no)
    if [ "${response}" == "Yes" ]; then
      local sops_age_private_key=$(get_sops_age_private_key "${sops_age_key_file}")
      kubectl create namespace "${namespace}"
      kubectl create secret generic sops-age --namespace="${namespace}" --from-literal=identity.agekey="${sops_age_private_key}"
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

cluster="${1:-dev}"

namespace="flux-system"
owner="biya-bi"
repository="rainbow-infra-engine"
branch="main"

sops_age_key_file=$(echo "${SOPS_AGE_KEY_FILE:-}" | xargs)

create_sops_age_secret "${namespace}" "${sops_age_key_file}"
bootstrap_flux "${namespace}" "${owner}" "${repository}" "${branch}" "${cluster}"