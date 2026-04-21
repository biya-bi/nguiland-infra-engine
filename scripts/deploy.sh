#!/usr/bin/env bash

set -euo pipefail

YELLOW='\033[0;33m'
NO_COLOR='\033[0m'

main() {
  if [ -z "${NGUILAND_INFRA_DEPLOY_REPOSITORY:-}" ]; then
    printf "${YELLOW}WARN: The NGUILAND_INFRA_DEPLOY_REPOSITORY environment variable is not set or is empty.${NO_COLOR}\n" >&2
    return 1
  fi

  if [ -z "${NGUILAND_INFRA_DEPLOY_REVISION:-}" ]; then
    printf "${YELLOW}WARN: The NGUILAND_INFRA_DEPLOY_REVISION environment variable is not set or is empty.${NO_COLOR}\n" >&2
    return 1
  fi

  local temp_dir
  temp_dir=$(mktemp -d)
  cleanup() {
    exit_code=$?
    if [ -n "${temp_dir:-}" ] && [ -d "$temp_dir" ]; then
      rm -rf "$temp_dir"
    fi
    printf 'Deployment complete.\n'
    return "$exit_code"
  }
  trap cleanup EXIT

  printf 'Cloning revision %s from repository %s into %s\n' "$NGUILAND_INFRA_DEPLOY_REVISION" "$NGUILAND_INFRA_DEPLOY_REPOSITORY" "$temp_dir"

  git clone --branch "$NGUILAND_INFRA_DEPLOY_REVISION" --depth 1 "$NGUILAND_INFRA_DEPLOY_REPOSITORY" "$temp_dir"
  cd "$temp_dir"

  local entrypoint="./scripts/entrypoint.sh"

  if [ ! -x "$entrypoint" ] && [ -f "$entrypoint" ]; then
    chmod +x "$entrypoint"
  fi

  "$entrypoint"
}

# Direct-execution guard: only invoke main when this script is executed directly,
# not when it is sourced into another shell.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi