#!/usr/bin/env bash
# SPEC.md todo markers: status, stable hashes and single ownership.
set -euo pipefail
cd "$(dirname "$0")/../.."
export PYTHONDONTWRITEBYTECODE=1
exec python3 test/cli/spec_marker.py
