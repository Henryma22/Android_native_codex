#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
MANIFEST=""
SCHEMA="$SCRIPT_DIR/rootfs-manifest.schema.json"
while (($#)); do
  case "$1" in
    --schema)
      [[ $# -ge 2 ]] || { echo "validate-manifest: --schema needs a path" >&2; exit 2; }
      SCHEMA=$2; shift 2 ;;
    --help|-h)
      echo "Usage: validate-manifest.sh MANIFEST [--schema SCHEMA]"; exit 0 ;;
    --*) echo "validate-manifest: unknown option: $1" >&2; exit 2 ;;
    *)
      [[ -z "$MANIFEST" ]] || { echo "validate-manifest: only one manifest is allowed" >&2; exit 2; }
      MANIFEST=$1; shift ;;
  esac
done
[[ -n "$MANIFEST" ]] || { echo "validate-manifest: manifest path is required" >&2; exit 2; }
exec "$PYTHON_BIN" "$SCRIPT_DIR/validate-manifest.py" "$MANIFEST" --schema "$SCHEMA"
