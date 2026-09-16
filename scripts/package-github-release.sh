#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RELEASE_TAG="${RELEASE_TAG:-hpnssh-18.11.0-macos26-arm64}"
RELEASE_DIR="${RELEASE_DIR:-${ROOT_DIR}/release/${RELEASE_TAG}}"
FORCE=0
REQUIRE_ALL=0
ALL_VARIANTS=0
PACKAGED=0
SKIPPED=0

usage() {
  cat <<'USAGE'
Usage: scripts/package-github-release.sh [options]

Package latest validated HPN-SSH build outputs into GitHub Release-ready
tarballs. Binaries that fail validation are skipped and recorded in SKIPPED.txt.

Options:
  --release-tag TAG   Release tag/directory name. Default: hpnssh-18.11.0-macos26-arm64.
  --release-dir PATH  Output directory. Default: ./release/<tag>.
  --force             Replace an existing release directory.
  --all-variants      Package every known local variant. Default: preferred AWS-LC + macOS zlib only.
  --require-all       Fail if any known variant cannot be packaged.
  -h, --help          Show this help.
USAGE
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

while (($#)); do
  case "$1" in
    --release-tag)
      [[ $# -ge 2 ]] || die "--release-tag requires a value"
      RELEASE_TAG="$2"
      RELEASE_DIR="${ROOT_DIR}/release/${RELEASE_TAG}"
      shift 2
      ;;
    --release-dir)
      [[ $# -ge 2 ]] || die "--release-dir requires a value"
      RELEASE_DIR="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --all-variants)
      ALL_VARIANTS=1
      shift
      ;;
    --require-all)
      REQUIRE_ALL=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

case "$RELEASE_DIR" in
  "$ROOT_DIR"/*) ;;
  *) die "Refusing to write release assets outside workspace: $RELEASE_DIR" ;;
esac

require_cmd codesign
require_cmd bfs
require_cmd date
require_cmd file
require_cmd mkdir
require_cmd otool
require_cmd shasum
require_cmd tar
require_cmd uu-sort

if [[ -e "$RELEASE_DIR" ]]; then
  [[ "$FORCE" -eq 1 ]] ||
    die "Release directory already exists: $RELEASE_DIR. Pass --force to replace it."
  rm -rf -- "$RELEASE_DIR"
fi

mkdir -p "$RELEASE_DIR/staging"

MANIFEST="${RELEASE_DIR}/MANIFEST.txt"
SKIPPED_FILE="${RELEASE_DIR}/SKIPPED.txt"
NOTES="${RELEASE_DIR}/RELEASE_NOTES.md"

: >"$MANIFEST"
: >"$SKIPPED_FILE"

latest_run() {
  local workdir="$1"
  local runs_dir="${ROOT_DIR}/${workdir}/runs"
  [[ -d "$runs_dir" ]] || return 0
  bfs "$runs_dir" -mindepth 1 -maxdepth 1 -type d -name 'hpn-*' -print | uu-sort -V | tail -n 1
}

skip_variant() {
  local name="$1"
  local reason="$2"
  SKIPPED=$((SKIPPED + 1))
  warn "Skipping ${name}: ${reason}"
  printf '%s: %s\n' "$name" "$reason" >>"$SKIPPED_FILE"
}

relative_path() {
  local path="$1"
  printf '%s\n' "${path#${ROOT_DIR}/}"
}

write_variant_readme() {
  local stage="$1"
  local name="$2"
  local label="$3"
  local run_rel="$4"
  local version="$5"

  cat >"${stage}/README.md" <<EOF
# ${label}

This archive contains ad-hoc signed HPN-SSH 18.11 arm64 binaries for macOS.

Variant: ${name}
Source run: ${run_rel}
Version: ${version}

Run:

\`\`\`sh
./bin/hpnssh -V
otool -L ./bin/hpnssh
\`\`\`

These binaries keep the upstream \`hpn\` command prefix and do not replace
Apple's system OpenSSH binaries.
EOF
}

copy_and_sign_binaries() {
  local src_dir="$1"
  local dest_dir="$2"
  local copied=0
  local candidate

  mkdir -p "$dest_dir"
  for candidate in "$src_dir"/hpn*; do
    [[ -f "$candidate" && -x "$candidate" ]] || continue
    cp -p "$candidate" "$dest_dir/"
    codesign --force --sign - "${dest_dir}/$(basename "$candidate")" >/dev/null 2>&1
    copied=$((copied + 1))
  done

  [[ "$copied" -gt 0 ]] || return 1
}

package_variant() {
  local name="$1"
  local label="$2"
  local workdir="$3"
  local run
  local src_dir
  local hpnssh_bin
  local version
  local stage
  local archive
  local run_rel

  run="$(latest_run "$workdir")"
  [[ -n "$run" ]] || {
    skip_variant "$name" "no build run found under ${workdir}/runs"
    return 0
  }

  src_dir="${run}/hpn-ssh"
  hpnssh_bin="${src_dir}/hpnssh"
  [[ -x "$hpnssh_bin" ]] || {
    skip_variant "$name" "missing executable hpnssh in $(relative_path "$src_dir")"
    return 0
  }

  if ! file "$hpnssh_bin" | grep -q 'arm64'; then
    skip_variant "$name" "hpnssh is not an arm64 Mach-O executable"
    return 0
  fi

  if otool -L "$hpnssh_bin" | grep -q 'libbsm'; then
    skip_variant "$name" "hpnssh still links libbsm"
    return 0
  fi

  if [[ "$name" == "hpnssh-awslc-system-zlib" ]]; then
    local hpnsftp_bin="${src_dir}/hpnsftp"
    [[ -x "$hpnsftp_bin" ]] || {
      skip_variant "$name" "missing executable hpnsftp in $(relative_path "$src_dir")"
      return 0
    }
    if ! otool -L "$hpnsftp_bin" | grep -q '/usr/lib/libedit[.][0-9].*dylib'; then
      skip_variant "$name" "hpnsftp does not link macOS system libedit"
      return 0
    fi
    if otool -L "$hpnsftp_bin" | grep -q '/opt/homebrew/.*/libedit'; then
      skip_variant "$name" "hpnsftp still links Homebrew libedit"
      return 0
    fi
  fi

  if ! version="$("$hpnssh_bin" -V 2>&1)"; then
    skip_variant "$name" "hpnssh -V failed: ${version}"
    return 0
  fi

  if [[ "$version" != *"_hpn18.11.0"* ]]; then
    skip_variant "$name" "unexpected version output: ${version}"
    return 0
  fi

  stage="${RELEASE_DIR}/staging/${name}"
  archive="${RELEASE_DIR}/${name}-${RELEASE_TAG}.tar.gz"
  run_rel="$(relative_path "$run")"
  mkdir -p "$stage"

  copy_and_sign_binaries "$src_dir" "${stage}/bin" || {
    skip_variant "$name" "no hpn-prefixed executables copied"
    return 0
  }

  printf '%s\n' "$version" >"${stage}/VERSION.txt"
  otool -L "${stage}/bin/hpnssh" >"${stage}/otool-hpnssh.txt"
  if [[ -x "${stage}/bin/hpnsftp" ]]; then
    otool -L "${stage}/bin/hpnsftp" >"${stage}/otool-hpnsftp.txt"
  fi
  codesign -dv "${stage}/bin/hpnssh" >"${stage}/codesign-hpnssh.txt" 2>&1 || true
  write_variant_readme "$stage" "$name" "$label" "$run_rel" "$version"

  (
    cd "${RELEASE_DIR}/staging"
    tar -czf "$archive" "$name"
  )

  printf 'variant=%s\nlabel=%s\nsource_run=%s\narchive=%s\nversion=%s\n\n' \
    "$name" "$label" "$run_rel" "$(basename "$archive")" "$version" >>"$MANIFEST"

  PACKAGED=$((PACKAGED + 1))
  printf 'packaged: %s\n' "$(basename "$archive")"
}

if [[ "$ALL_VARIANTS" -eq 1 ]]; then
  package_variant hpnssh-openssl3 "HPN-SSH with OpenSSL 3" build
  package_variant hpnssh-awslc "HPN-SSH with AWS-LC" build-awslc
  package_variant hpnssh-awslc-system-zlib "HPN-SSH with AWS-LC and macOS zlib" build-awslc-system-zlib
  package_variant hpnssh-awslc-zlibng "HPN-SSH with AWS-LC and zlib-ng" build-awslc-zlibng
else
  package_variant hpnssh-awslc-system-zlib "HPN-SSH with AWS-LC and macOS zlib" build-awslc-system-zlib
fi

if [[ "$PACKAGED" -eq 0 ]]; then
  die "No variants were packaged. See $SKIPPED_FILE"
fi

if [[ "$REQUIRE_ALL" -eq 1 && "$SKIPPED" -gt 0 ]]; then
  die "Some variants were skipped. See $SKIPPED_FILE"
fi

if [[ "$SKIPPED" -eq 0 ]]; then
  printf 'No variants skipped.\n' >"$SKIPPED_FILE"
fi

(
  cd "$RELEASE_DIR"
  shasum -a 256 ./*.tar.gz >SHA256SUMS
)

cat >"$NOTES" <<EOF
# ${RELEASE_TAG}

This release contains validated HPN-SSH 18.11 macOS arm64 binary archives.

Packaged variants: ${PACKAGED}
Skipped variants: ${SKIPPED}
Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')

## Runtime Requirement

\`\`\`sh
brew install aws-lc
\`\`\`

The preferred archive uses Homebrew AWS-LC for \`libcrypto\`, macOS system
\`zlib\`, and macOS system \`libedit\` for \`hpnsftp\`.

## Assets

\`\`\`text
$(cd "$RELEASE_DIR" && ls -1 *.tar.gz SHA256SUMS MANIFEST.txt SKIPPED.txt RELEASE_NOTES.md)
\`\`\`

Use \`SHA256SUMS\` to verify downloaded archives:

\`\`\`sh
shasum -a 256 -c SHA256SUMS
\`\`\`
EOF

rm -rf -- "${RELEASE_DIR}/staging"

printf 'Release directory: %s\n' "$RELEASE_DIR"
printf 'Packaged variants: %s\n' "$PACKAGED"
printf 'Skipped variants: %s\n' "$SKIPPED"
