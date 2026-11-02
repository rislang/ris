#!/usr/bin/env bash
# What ris's CI jobs add to crystallang/crystal:1.21.0-build: LLVM 23 (21 and
# 22 miscompile, see LLVM.md) and the tools test/ris/check.sh calls.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  ca-certificates curl netcat-openbsd nodejs python3 python3-cryptography \
  xz-utils zstd > /dev/null
curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key \
  > /etc/apt/trusted.gpg.d/apt.llvm.org.asc
echo "deb http://apt.llvm.org/noble/ llvm-toolchain-noble-23 main" \
  > /etc/apt/sources.list.d/llvm.list
apt-get update -qq
apt-get install -y -qq --no-install-recommends llvm-23-dev > /dev/null
llvm-config-23 --version
