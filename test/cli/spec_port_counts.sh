#!/usr/bin/env bash
# Temporary loss and mutation gate for doc/drafts/spec-port/.
set -euo pipefail
cd "$(dirname "$0")/../.."
exec python3 test/cli/spec_port_counts.py "$@"
