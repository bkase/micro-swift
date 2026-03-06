#!/usr/bin/env bash
set -euo pipefail

repo_root() {
  local path="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  echo "$path"
}

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "missing command: $name" >&2
    return 1
  fi
}

run_or_dry() {
  local command="$1"
  shift
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "$command $*"
    return 0
  fi
  "$command" "$@"
}
