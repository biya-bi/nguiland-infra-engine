#!/usr/bin/env bash

set -euo pipefail

main() {
  if [ -z "${NGUILAND_INFRA_DEPLOY_REPOSITORY:-}" ]; then
    printf '\033[33mWarning: The NGUILAND_INFRA_DEPLOY_REPOSITORY environment variable is not set or is empty.\033[0m\n' >&2
    return 1
  fi

  if [ -z "${NGUILAND_INFRA_DEPLOY_REVISION:-}" ]; then
    printf '\033[33mWarning: The NGUILAND_INFRA_DEPLOY_REVISION environment variable is not set or is empty.\033[0m\n' >&2
    return 1
  fi

  local TEMP_DIR
  TEMP_DIR=$(mktemp -d)
  cleanup() {
    exit_code=$?
    if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
      rm -rf "$TEMP_DIR"
    fi
    printf 'Deployment complete.\n'
    return "$exit_code"
  }
  trap cleanup EXIT

  printf 'Cloning revision %s from repository %s into %s\n' "$NGUILAND_INFRA_DEPLOY_REVISION" "$NGUILAND_INFRA_DEPLOY_REPOSITORY" "$TEMP_DIR"

  git clone --branch "$NGUILAND_INFRA_DEPLOY_REVISION" --depth 1 "$NGUILAND_INFRA_DEPLOY_REPOSITORY" "$TEMP_DIR"
  cd "$TEMP_DIR"

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