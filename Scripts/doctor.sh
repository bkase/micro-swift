#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--json" ]]; then
  cat <<JSON
{
  "status": "ok",
  "version": "$(swiftc -version 2>/dev/null | tr -d '\n' || echo unknown)",
  "os": "$(uname -sr)"
}
JSON
  exit 0
fi

echo "micro-swift doctor"
echo "status: ok"
echo "os: $(uname -sr)"
echo "swift: $(swiftc -version 2>/dev/null | tr -d '\n' || echo unknown)"
