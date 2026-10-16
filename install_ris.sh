#!/bin/sh
# Installs the latest ris release, with no Crystal or LLVM needed:
#
#   curl -fsSL \
#     https://raw.githubusercontent.com/rislang/ris/main/install_ris.sh | sh
#
# The release unpacks into its own directory, PREFIX/lib/ris, and PREFIX/bin/ris
# is linked into it, so an installed iyi is left alone.
#
# RIS_PREFIX       default ~/.local
# RIS_VERSION      a release to pin, e.g. 0.1.0; default is the latest release
# RIS_RELEASE_URL  where the release's files are, default the GitHub release;
#                  a directory (file://) installs a tarball before release
set -eu

repo="rislang/ris"
prefix="${RIS_PREFIX:-$HOME/.local}"
version="${RIS_VERSION:-}"

say() { printf '%s\n' "$*" >&2; }
die() { say "install_ris.sh: $*"; exit 1; }
from_source="build from source with make install_ris (README.md)"

for tool in curl tar; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is required"
done

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) target=linux-x86_64 ;;
  Darwin-arm64) target=darwin-arm64 ;;
  *) die "no release for $(uname -s) $(uname -m), only linux-x86_64 and" \
       "darwin-arm64; $from_source" ;;
esac

# The latest release, by GitHub's redirect: no token, no rate limit.
if [ -z "$version" ] && [ -z "${RIS_RELEASE_URL:-}" ]; then
  tag_url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
    "https://github.com/$repo/releases/latest")" ||
    die "could not resolve the latest release of $repo"
  version="${tag_url##*/tag/ris-v}"
  [ "$version" != "$tag_url" ] ||
    die "$repo has no ris release yet; $from_source"
fi
version="${version#v}"

releases="https://github.com/$repo/releases/download"
base="${RIS_RELEASE_URL:-$releases/ris-v$version}"
if [ -z "$version" ]; then
  # A local directory names its one tarball; take the version from it.
  asset="$(cd "${base#file://}" && ls ris-*-"$target".tar.gz | head -n 1)" ||
    die "no ris-*-$target.tar.gz in $base"
else
  asset="ris-$version-$target.tar.gz"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

say "ris: $asset"
curl -fSL --progress-bar -o "$tmp/$asset" "$base/$asset" ||
  die "download failed: $base/$asset"

# Checked against the release's SHA256SUMS before anything is unpacked.
if curl -fsSL -o "$tmp/SHA256SUMS" "$base/SHA256SUMS" 2>/dev/null; then
  expected="$(awk -v name="$asset" \
    '$2 == name || $2 == "*" name { print $1; exit }' "$tmp/SHA256SUMS")"
  [ -n "$expected" ] || die "the release's SHA256SUMS has no line for $asset"
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$tmp/$asset" | awk '{ print $1 }')"
  else
    actual="$(shasum -a 256 "$tmp/$asset" | awk '{ print $1 }')"
  fi
  [ "$actual" = "$expected" ] ||
    die "$asset does not match SHA256SUMS: expected $expected," \
        "got $actual; nothing was unpacked"
  say "verified: sha256 $actual"
else
  say "note: no SHA256SUMS beside the tarball; it was not verified"
fi

home="$prefix/lib/ris"
mkdir -p "$prefix/bin" "$prefix/lib" 2>/dev/null && [ -w "$prefix/lib" ] ||
  die "$prefix is not writable; set RIS_PREFIX to a directory that is"
rm -rf "$home.new"
mkdir "$home.new"
tar -xzf "$tmp/$asset" -C "$home.new"
"$home.new/bin/ris" version >/dev/null || die "the unpacked ris does not start"
rm -rf "$home"
mv "$home.new" "$home"
ln -sf "$home/bin/ris" "$prefix/bin/ris"

say "installed $prefix/bin/ris ($("$prefix/bin/ris" version | head -n 1))"
command -v cc >/dev/null 2>&1 ||
  say "note: no C compiler on PATH; ris links through cc: install gcc or clang"
case ":$PATH:" in
  *":$prefix/bin:"*) ;;
  *) say "note: add $prefix/bin to PATH:" \
       "export PATH=\"$prefix/bin:\$PATH\"" ;;
esac
say "docs and samples: $home/share/ris"
