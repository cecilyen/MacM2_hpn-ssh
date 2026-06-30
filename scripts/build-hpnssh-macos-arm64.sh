#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REPO_URL="${HPNSSH_REPO_URL:-https://github.com/rapier1/hpn-ssh.git}"
VERSION_SERIES="${HPNSSH_VERSION_SERIES:-18.9}"
TAG="${HPNSSH_TAG:-}"
PREFIX="${HPNSSH_PREFIX:-/opt/hpnssh}"
WORKDIR="${HPNSSH_WORKDIR:-${ROOT_DIR}/build}"
HPN_MARKER="${HPNSSH_VERSION_MARKER:-}"
CRYPTO_NAME="${HPNSSH_CRYPTO_NAME:-OpenSSL 3}"
CRYPTO_FORMULA="${HPNSSH_CRYPTO_FORMULA:-openssl@3}"
CRYPTO_PREFIX_OVERRIDE="${HPNSSH_CRYPTO_PREFIX:-${OPENSSL_PREFIX:-}}"
CRYPTO_HEADER="${HPNSSH_CRYPTO_HEADER:-include/openssl/ssl.h}"
CRYPTO_LIB_GLOB="${HPNSSH_CRYPTO_LIB_GLOB:-lib/libcrypto.*}"
ZLIB_MODE="${HPNSSH_ZLIB_MODE:-homebrew}"
LIBEDIT_MODE="${HPNSSH_LIBEDIT_MODE:-homebrew}"
KERBEROS_ROOT="${HPNSSH_KERBEROS_ROOT:-/usr}"
KRB5CONF="${KRB5CONF:-${KERBEROS_ROOT}/bin/krb5-config}"
LOG_BASENAME="${HPNSSH_LOG_BASENAME:-hpnssh-build}"
INSTALL=0
RUN_TESTS=0
EXTRA_CONFIGURE_ARGS=()

usage() {
  cat <<'USAGE'
Usage: scripts/build-hpnssh-macos-arm64.sh [options] [-- configure-arg ...]

Build HPN-SSH from the official rapier1/hpn-ssh repository for macOS on
Apple Silicon with arm64, Homebrew libcrypto, Homebrew zlib, PAM, and Kerberos.

Options:
  --tag TAG              Build an explicit tag, for example hpn-18.9.0.
  --version-series X.Y   Resolve the latest hpn-X.Y.z tag. Default: 18.9.
  --prefix PATH          Configure isolated install prefix. Default: /opt/hpnssh.
  --workdir PATH         Build workspace. Default: ./build.
  --install              Run make install after a successful build.
  --run-tests            Run make tests after build.
  -h, --help             Show this help.

Environment:
  HPNSSH_REPO_URL        Override upstream Git repository URL.
  HPNSSH_TAG             Same as --tag.
  HPNSSH_VERSION_SERIES  Same as --version-series.
  HPNSSH_PREFIX          Same as --prefix.
  HPNSSH_WORKDIR         Same as --workdir.
  HPNSSH_VERSION_MARKER  Optional marker appended to SSH_HPN. Default: disabled.
  HPNSSH_CPU_TARGET      Override the detected Apple -mcpu target, e.g. apple-m2.
  HPNSSH_CRYPTO_NAME     Human-readable crypto provider name. Default: OpenSSL 3.
  HPNSSH_CRYPTO_FORMULA  Homebrew formula for libcrypto. Default: openssl@3.
  HPNSSH_CRYPTO_PREFIX   Explicit libcrypto prefix. OPENSSL_PREFIX is also honored.
  HPNSSH_ZLIB_MODE       zlib provider: homebrew or system. Default: homebrew.
  HPNSSH_LIBEDIT_MODE    libedit provider: homebrew, system, or disabled. Default: homebrew.
  HPNSSH_BASE_OPT_FLAGS  Override base C/C++ optimization flags.
  HPNSSH_BASE_LDFLAGS    Override base linker optimization flags.
  HPNSSH_KERBEROS_ROOT   Kerberos root passed to configure. Default: /usr.
  HPNSSH_LOG_BASENAME    Build log basename. Default: hpnssh-build.
  CC, CXX                Override Apple compiler paths.

Examples:
  scripts/build-hpnssh-macos-arm64.sh
  scripts/build-hpnssh-macos-arm64.sh --prefix /usr/local/hpnssh
  scripts/build-hpnssh-macos-arm64.sh --tag hpn-18.9.0
USAGE
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

abs_path() {
  local path="$1"
  if [[ -d "$path" ]]; then
    (cd "$path" && pwd)
  else
    local parent
    parent="$(dirname "$path")"
    local base
    base="$(basename "$path")"
    (cd "$parent" && printf '%s/%s\n' "$(pwd)" "$base")
  fi
}

rewrite_with_awk() {
  local file="$1"
  shift

  local tmp
  tmp="$(mktemp -t hpnssh-rewrite.XXXXXX)"
  awk "$@" "$file" > "$tmp"
  mv "$tmp" "$file"
}

macho_linkage() {
  local binary="$1"
  local pattern="$2"

  "$OTOOL" -L "$binary" |
    awk -v pattern="$pattern" '$0 ~ pattern { print $1 }' |
    paste -sd ' ' -
}

require_linkage_contains() {
  local label="$1"
  local pattern="$2"
  local expected="$3"
  local linkage

  linkage="$(macho_linkage "$HPNSSH_BIN" "$pattern")"
  log "$label linkage: ${linkage:-not found}"
  [[ "$linkage" == *"$expected"* ]] ||
    die "Validation failed: ${label} linkage does not contain ${expected}"
}

require_binary_linkage_contains() {
  local binary="$1"
  local label="$2"
  local pattern="$3"
  local expected="$4"
  local linkage

  linkage="$(macho_linkage "$binary" "$pattern")"
  log "$(basename "$binary") $label linkage: ${linkage:-not found}"
  [[ "$linkage" == *"$expected"* ]] ||
    die "Validation failed: $(basename "$binary") ${label} linkage does not contain ${expected}"
}

reject_linkage() {
  local label="$1"
  local pattern="$2"
  local linkage

  linkage="$(macho_linkage "$HPNSSH_BIN" "$pattern")"
  log "$label linkage: ${linkage:-not found}"
  [[ -z "$linkage" ]] ||
    die "Validation failed: unexpected ${label} linkage: $linkage"
}

reject_binary_linkage() {
  local binary="$1"
  local label="$2"
  local pattern="$3"
  local linkage

  linkage="$(macho_linkage "$binary" "$pattern")"
  log "$(basename "$binary") $label linkage: ${linkage:-not found}"
  [[ -z "$linkage" ]] ||
    die "Validation failed: unexpected $(basename "$binary") ${label} linkage: $linkage"
}

while (($#)); do
  case "$1" in
    --tag)
      [[ $# -ge 2 ]] || die "--tag requires a value"
      TAG="$2"
      shift 2
      ;;
    --version-series)
      [[ $# -ge 2 ]] || die "--version-series requires a value"
      VERSION_SERIES="$2"
      shift 2
      ;;
    --prefix)
      [[ $# -ge 2 ]] || die "--prefix requires a value"
      PREFIX="$2"
      shift 2
      ;;
    --workdir)
      [[ $# -ge 2 ]] || die "--workdir requires a value"
      WORKDIR="$2"
      shift 2
      ;;
    --install)
      INSTALL=1
      shift
      ;;
    --run-tests)
      RUN_TESTS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      EXTRA_CONFIGURE_ARGS+=("$@")
      break
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

[[ "$VERSION_SERIES" =~ ^[0-9]+[.][0-9]+$ ]] || die "--version-series must look like 18.9"
if [[ -n "$TAG" ]]; then
  [[ "$TAG" =~ ^hpn-[0-9]+[.][0-9]+[.][0-9]+$ ]] || die "--tag must look like hpn-18.9.0"
fi
case "$ZLIB_MODE" in
  homebrew|system) ;;
  *) die "HPNSSH_ZLIB_MODE must be either homebrew or system" ;;
esac
case "$LIBEDIT_MODE" in
  homebrew|system|disabled) ;;
  *) die "HPNSSH_LIBEDIT_MODE must be homebrew, system, or disabled" ;;
esac

WORKDIR="$(abs_path "$WORKDIR")"
PREFIX="$(abs_path "$PREFIX")"
LOG_DIR="${ROOT_DIR}/logs"
mkdir -p "$LOG_DIR" "$WORKDIR"
LOG_FILE="${LOG_DIR}/${LOG_BASENAME}-$(date '+%Y%m%d-%H%M%S').log"
printf 'Build log: %s\n' "$LOG_FILE"
exec >>"$LOG_FILE" 2>&1

log "HPN-SSH macOS arm64 build started"
log "Repository: $REPO_URL"
log "Version series: $VERSION_SERIES"
log "Prefix: $PREFIX"
log "Workdir: $WORKDIR"
log "Version marker: ${HPN_MARKER:-disabled}"
log "Crypto provider: $CRYPTO_NAME"
log "Crypto formula: $CRYPTO_FORMULA"
log "zlib mode: $ZLIB_MODE"
log "libedit mode: $LIBEDIT_MODE"
log "Log: $LOG_FILE"

require_cmd git
require_cmd awk
require_cmd sed
require_cmd sort
require_cmd tail
require_cmd make
require_cmd xcrun
require_cmd file
require_cmd "$KRB5CONF"

BREW_BIN="${BREW_BIN:-$(command -v brew || true)}"
[[ -n "$BREW_BIN" ]] || die "Homebrew is required; install it or set BREW_BIN."
export HOMEBREW_NO_AUTO_UPDATE="${HOMEBREW_NO_AUTO_UPDATE:-1}"
export HOMEBREW_NO_INSTALL_FROM_API="${HOMEBREW_NO_INSTALL_FROM_API:-1}"

HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-$("$BREW_BIN" --prefix 2>/dev/null || true)}"
if [[ -z "$HOMEBREW_PREFIX" ]]; then
  HOMEBREW_PREFIX="$(cd "$(dirname "$BREW_BIN")/.." && pwd)"
fi

brew_prefix() {
  local formula="$1"
  local opt_prefix="${HOMEBREW_PREFIX}/opt/${formula}"
  if [[ -d "$opt_prefix" ]]; then
    printf '%s\n' "$opt_prefix"
    return 0
  fi
  "$BREW_BIN" --prefix "$formula" 2>/dev/null
}

formula_has_files() {
  local prefix="$1"
  local header="$2"
  local lib_glob="$3"
  [[ -d "$prefix" && -f "${prefix}/${header}" ]] || return 1
  compgen -G "${prefix}/${lib_glob}" >/dev/null
}

is_awslc_build() {
  [[ "$CRYPTO_FORMULA" == "aws-lc" || "$CRYPTO_PREFIX" == *"/aws-lc"* || "$CRYPTO_NAME" == *"AWS-LC"* ]]
}

ensure_brew_formula() {
  local formula="$1"
  local header="$2"
  local lib_glob="$3"
  local prefix
  prefix="$(brew_prefix "$formula" || true)"

  if formula_has_files "$prefix" "$header" "$lib_glob"; then
    printf '%s\n' "$prefix"
    return 0
  fi

  log "Homebrew formula $formula is missing required files; attempting brew install $formula" >&2
  if [[ ! -w "$HOMEBREW_PREFIX" || ! -w "${HOMEBREW_PREFIX}/Cellar" || ! -w "${HOMEBREW_PREFIX}/opt" ]]; then
    die "Homebrew formula $formula is not installed and ${HOMEBREW_PREFIX} is not writable by $(id -un). Ask the Homebrew owner or an administrator to run: ${BREW_BIN} install ${formula}"
  fi

  "$BREW_BIN" install "$formula" >&2
  prefix="$(brew_prefix "$formula" || true)"
  formula_has_files "$prefix" "$header" "$lib_glob" || die "Installed $formula but required files are still missing under $prefix"
  printf '%s\n' "$prefix"
}

CRYPTO_PREFIX="${CRYPTO_PREFIX_OVERRIDE:-$(ensure_brew_formula "$CRYPTO_FORMULA" "$CRYPTO_HEADER" "$CRYPTO_LIB_GLOB")}"
if [[ "$ZLIB_MODE" == "system" ]]; then
  ZLIB_PREFIX="${ZLIB_PREFIX:-/usr}"
else
  ZLIB_PREFIX="${ZLIB_PREFIX:-$(ensure_brew_formula zlib include/zlib.h 'lib/libz.*')}"
fi
AUTOCONF_PREFIX="${AUTOCONF_PREFIX:-$(brew_prefix autoconf)}"
AUTOMAKE_PREFIX="${AUTOMAKE_PREFIX:-$(brew_prefix automake)}"
LIBTOOL_PREFIX="${LIBTOOL_PREFIX:-$(brew_prefix libtool)}"
PKGCONF_PREFIX="${PKGCONF_PREFIX:-$(brew_prefix pkg-config || brew_prefix pkgconf || true)}"
case "$LIBEDIT_MODE" in
  homebrew)
    LIBEDIT_PREFIX="${LIBEDIT_PREFIX:-$(brew_prefix libedit || true)}"
    ;;
  system)
    LIBEDIT_PREFIX="${LIBEDIT_PREFIX:-/usr}"
    ;;
  disabled)
    LIBEDIT_PREFIX=""
    ;;
esac

formula_has_files "$CRYPTO_PREFIX" "$CRYPTO_HEADER" "$CRYPTO_LIB_GLOB" || die "$CRYPTO_NAME headers/libs not found under HPNSSH_CRYPTO_PREFIX=$CRYPTO_PREFIX"
if [[ "$ZLIB_MODE" == "homebrew" ]]; then
  formula_has_files "$ZLIB_PREFIX" include/zlib.h 'lib/libz.*' || die "zlib headers/libs not found under ZLIB_PREFIX=$ZLIB_PREFIX"
fi
[[ -d "$AUTOCONF_PREFIX/bin" ]] || die "Homebrew autoconf not found."
[[ -d "$AUTOMAKE_PREFIX/bin" ]] || die "Homebrew automake not found."
[[ -d "$LIBTOOL_PREFIX/bin" ]] || die "Homebrew libtool not found."

PATH="${AUTOCONF_PREFIX}/bin:${AUTOMAKE_PREFIX}/bin:${LIBTOOL_PREFIX}/bin:${PATH}"
if [[ -n "$PKGCONF_PREFIX" && -d "$PKGCONF_PREFIX/bin" ]]; then
  PATH="${PKGCONF_PREFIX}/bin:${PATH}"
fi
export PATH

require_cmd autoreconf
require_cmd aclocal
require_cmd automake
require_cmd autoconf
require_cmd glibtoolize

SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path)}"
[[ -d "$SDKROOT" ]] || die "macOS SDK path not found: $SDKROOT"
export SDKROOT
if [[ "$ZLIB_MODE" == "system" ]]; then
  [[ -f "${SDKROOT}/usr/include/zlib.h" ]] || die "system zlib header not found in SDK: ${SDKROOT}/usr/include/zlib.h"
  [[ -f "${SDKROOT}/usr/lib/libz.tbd" || -f "${SDKROOT}/usr/lib/libz.1.tbd" ]] ||
    die "system zlib linker stub not found in SDK: ${SDKROOT}/usr/lib/libz.tbd"
fi
if [[ "$LIBEDIT_MODE" == "system" ]]; then
  [[ -f "${SDKROOT}/usr/include/histedit.h" ]] || die "system libedit header not found in SDK: ${SDKROOT}/usr/include/histedit.h"
  [[ -f "${SDKROOT}/usr/lib/libedit.tbd" || -f "${SDKROOT}/usr/lib/libedit.3.tbd" ]] ||
    die "system libedit linker stub not found in SDK: ${SDKROOT}/usr/lib/libedit.tbd"
fi

CC="${CC:-$(xcrun -find clang)}"
CXX="${CXX:-$(xcrun -find clang++)}"
AR="${AR:-$(xcrun -find ar)}"
RANLIB="${RANLIB:-$(xcrun -find ranlib)}"
STRIP="${STRIP:-$(xcrun -find strip)}"
OTOOL="${OTOOL:-$(xcrun -find otool)}"
CODESIGN="${CODESIGN:-/usr/bin/codesign}"
export CC CXX AR RANLIB STRIP OTOOL CODESIGN
require_cmd "$CODESIGN"

compiler_supports_cflag() {
  local tmp
  tmp="$(mktemp -t hpnssh-cflag.XXXXXX.c)"
  local obj="${tmp}.o"
  printf 'int main(void) { return 0; }\n' > "$tmp"
  "$CC" "$@" -x c "$tmp" -c -o "$obj" >/dev/null 2>&1
  local rc=$?
  rm -f "$tmp" "$obj"
  return "$rc"
}

compiler_supports_linkflag() {
  local tmp
  tmp="$(mktemp -t hpnssh-ldflag.XXXXXX.c)"
  local bin="${tmp}.bin"
  printf 'int main(void) { return 0; }\n' > "$tmp"
  "$CC" "$@" -x c "$tmp" -o "$bin" >/dev/null 2>&1
  local rc=$?
  rm -f "$tmp" "$bin"
  return "$rc"
}

ARCH_FLAGS="-arch arm64"
compiler_supports_cflag $ARCH_FLAGS || die "Compiler does not accept required ARM64 flag: $ARCH_FLAGS"
compiler_supports_linkflag $ARCH_FLAGS || die "Linker does not accept required ARM64 flag: $ARCH_FLAGS"
compiler_supports_cflag -flto || die "Compiler does not accept required LTO flag: -flto"
compiler_supports_linkflag -flto || die "Linker does not accept required LTO flag: -flto"

detect_cpu_brand() {
  local brand
  brand="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
  if [[ -z "$brand" ]] && command -v system_profiler >/dev/null 2>&1; then
    brand="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/^[[:space:]]*Chip:/ { print $2; exit }')"
  fi
  if [[ -z "$brand" ]]; then
    brand="$(sysctl -n hw.model 2>/dev/null || uname -m)"
  fi
  printf '%s\n' "$brand"
}

CPU_BRAND="$(detect_cpu_brand)"

CPU_CANDIDATES=()
if [[ -n "${HPNSSH_CPU_TARGET:-}" ]]; then
  CPU_CANDIDATES=("$HPNSSH_CPU_TARGET")
else
  case "$CPU_BRAND" in
    *M5*) CPU_CANDIDATES=(apple-m5 apple-m4 apple-m3 apple-m2 apple-m1) ;;
    *M4*) CPU_CANDIDATES=(apple-m4 apple-m3 apple-m2 apple-m1) ;;
    *M3*) CPU_CANDIDATES=(apple-m3 apple-m2 apple-m1) ;;
    *M2*) CPU_CANDIDATES=(apple-m2 apple-m1) ;;
    *M1*) CPU_CANDIDATES=(apple-m1) ;;
    *) CPU_CANDIDATES=(apple-m4 apple-m3 apple-m2 apple-m1) ;;
  esac
fi

CPU_FLAG=""
for cpu in "${CPU_CANDIDATES[@]}"; do
  if compiler_supports_cflag "-mcpu=${cpu}"; then
    CPU_FLAG="-mcpu=${cpu}"
    break
  fi
done
[[ -n "$CPU_FLAG" ]] || warn "No Apple -mcpu target was accepted by the compiler; continuing with ARM64 arch flags only."

NCPU="$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
[[ "$NCPU" =~ ^[0-9]+$ && "$NCPU" -gt 0 ]] || NCPU=1

if [[ -n "${HPNSSH_BASE_OPT_FLAGS:-}" ]]; then
  BASE_OPT_FLAGS="${HPNSSH_BASE_OPT_FLAGS}"
else
  BASE_OPT_FLAGS="${ARCH_FLAGS} -O3 -flto -g0"
  if [[ -n "$CPU_FLAG" ]]; then
    BASE_OPT_FLAGS="${BASE_OPT_FLAGS} ${CPU_FLAG}"
  fi
fi
BASE_LINK_FLAGS="${HPNSSH_BASE_LDFLAGS:-${ARCH_FLAGS} -flto}"

ZLIB_CPPFLAGS=""
ZLIB_LDFLAGS=""
ZLIB_PKG_CONFIG_PATH=""
ZLIB_LINKAGE_EXPECTED="${ZLIB_PREFIX}/lib/libz"
if [[ "$ZLIB_MODE" == "homebrew" ]]; then
  ZLIB_CPPFLAGS="-I${ZLIB_PREFIX}/include"
  ZLIB_LDFLAGS="-L${ZLIB_PREFIX}/lib -Wl,-rpath,${ZLIB_PREFIX}/lib"
  ZLIB_PKG_CONFIG_PATH="${ZLIB_PREFIX}/lib/pkgconfig:"
else
  ZLIB_LINKAGE_EXPECTED="/usr/lib/libz"
fi

export CFLAGS="${CFLAGS:-} ${BASE_OPT_FLAGS}"
export CXXFLAGS="${CXXFLAGS:-} ${BASE_OPT_FLAGS}"
export CPPFLAGS="${CPPFLAGS:-} -isysroot ${SDKROOT} -I${CRYPTO_PREFIX}/include ${ZLIB_CPPFLAGS}"
export LDFLAGS="${LDFLAGS:-} ${BASE_LINK_FLAGS} -isysroot ${SDKROOT} -Wl,-search_paths_first -L${CRYPTO_PREFIX}/lib ${ZLIB_LDFLAGS} -Wl,-rpath,${CRYPTO_PREFIX}/lib -framework Kerberos"
export PKG_CONFIG_PATH="${CRYPTO_PREFIX}/lib/pkgconfig:${ZLIB_PKG_CONFIG_PATH}${PKG_CONFIG_PATH:-}"
export KRB5CONF
if is_awslc_build; then
  export CPPFLAGS="${CPPFLAGS} -DHPNSSH_AWSLC"
fi

LIBEDIT_CONFIGURE_ARG=()
LIBEDIT_LINKAGE_EXPECTED=""
case "$LIBEDIT_MODE" in
  homebrew)
    if formula_has_files "$LIBEDIT_PREFIX" include/histedit.h 'lib/libedit.*'; then
      export CPPFLAGS="${CPPFLAGS} -I${LIBEDIT_PREFIX}/include"
      export LDFLAGS="${LDFLAGS} -L${LIBEDIT_PREFIX}/lib -Wl,-rpath,${LIBEDIT_PREFIX}/lib"
      export PKG_CONFIG_PATH="${LIBEDIT_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH}"
      LIBEDIT_CONFIGURE_ARG=("--with-libedit=${LIBEDIT_PREFIX}")
      LIBEDIT_LINKAGE_EXPECTED="${LIBEDIT_PREFIX}/lib/libedit"
    elif [[ -n "$LIBEDIT_PREFIX" ]]; then
      warn "Homebrew libedit prefix exists but headers/libs were not found under $LIBEDIT_PREFIX; building without libedit."
    fi
    ;;
  system)
    LIBEDIT_CONFIGURE_ARG=("--with-libedit=/usr")
    LIBEDIT_LINKAGE_EXPECTED="/usr/lib/libedit"
    ;;
  disabled)
    LIBEDIT_CONFIGURE_ARG=("--without-libedit")
    ;;
esac

log "Compiler: $CC"
log "CFLAGS: $CFLAGS"
log "CXXFLAGS: $CXXFLAGS"
log "CPPFLAGS: $CPPFLAGS"
log "LDFLAGS: $LDFLAGS"
log "PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
log "SDKROOT: $SDKROOT"
log "Kerberos root: $KERBEROS_ROOT"
log "Kerberos config: $KRB5CONF"
log "CPU brand/model: $CPU_BRAND"
log "Selected CPU flag: ${CPU_FLAG:-none}"
log "Parallel jobs: $NCPU"
log "Crypto prefix: $CRYPTO_PREFIX"
log "zlib prefix: $ZLIB_PREFIX"
log "zlib linkage expected: $ZLIB_LINKAGE_EXPECTED"
log "libedit prefix: ${LIBEDIT_PREFIX:-not used}"
log "libedit linkage expected: ${LIBEDIT_LINKAGE_EXPECTED:-not used}"
if is_awslc_build; then
  warn "AWS-LC builds disable PKCS#11 in this HPN-SSH source tree; smart-card/token workflows need separate validation."
  warn "AWS-LC lacks EVP_CIPHER_meth_*; AES-CTR-MT hook is disabled and AWS-LC native AES-CTR is used."
  warn "AWS-LC lacks the EVP_chacha20 API required by HPN-SSH's ChaCha20-Poly1305-MT hook; that MT cipher is not advertised."
fi

resolve_latest_tag() {
  local series="$1"
  local refs
  refs="$(git ls-remote --tags "$REPO_URL" "refs/tags/hpn-${series}.*")"
  [[ -n "$refs" ]] || die "No hpn-${series}.x tags found in $REPO_URL"
  printf '%s\n' "$refs" |
    sed -E 's#^[[:xdigit:]]+[[:space:]]+refs/tags/(hpn-([0-9]+)[.]([0-9]+)[.]([0-9]+))(\^\{\})?$#\2 \3 \4 \1#' |
    awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ { print }' |
    sort -n -k1,1 -k2,2 -k3,3 |
    awk '{print $4}' |
    tail -n 1
}

if [[ -z "$TAG" ]]; then
  TAG="$(resolve_latest_tag "$VERSION_SERIES")"
fi
[[ -n "$TAG" ]] || die "Could not resolve HPN-SSH tag."
[[ "$TAG" == hpn-"$VERSION_SERIES".* ]] || die "Resolved tag $TAG does not match requested series $VERSION_SERIES"
log "Resolved tag: $TAG"
HPN_VERSION="${TAG#hpn-}"
EXPECTED_HPN_SUFFIX="_hpn${HPN_VERSION}"
log "Expected HPN version suffix: $EXPECTED_HPN_SUFFIX"

RUN_ID="$(date '+%Y%m%d-%H%M%S')"
RUN_DIR="${WORKDIR}/runs/${TAG}-${RUN_ID}"
SRC_DIR="${RUN_DIR}/hpn-ssh"
mkdir -p "$RUN_DIR"

log "Cloning $TAG into $SRC_DIR"
git clone --depth 1 --branch "$TAG" "$REPO_URL" "$SRC_DIR"
COMMIT_SHA="$(git -C "$SRC_DIR" rev-parse HEAD)"
log "Source commit: $COMMIT_SHA"

patch_version_marker() {
  local src="$1"

  [[ -n "$HPN_MARKER" ]] || return 0

  local version_h="${src}/version.h"
  [[ -f "$version_h" ]] || die "Expected upstream version header not found: $version_h"
  if grep -q "$HPN_MARKER" "$version_h"; then
    return 0
  fi

  log "Appending version marker to SSH_HPN: $HPN_MARKER"
  rewrite_with_awk "$version_h" -v marker="$HPN_MARKER" '
    /^#define[ \t]+SSH_HPN[ \t]+"/ && index($0, marker) == 0 {
      sub(/"$/, "_" marker "\"")
    }
    { print }
  '
}

patch_default_port() {
  local src="$1"
  local ssh_h="${src}/ssh.h"
  local sshd_config="${src}/sshd_config"

  [[ -f "$ssh_h" ]] || die "Expected upstream ssh.h not found: $ssh_h"
  log "Setting HPNSSH_DEFAULT_PORT to 22"
  rewrite_with_awk "$ssh_h" '
    /^#define[ \t]+HPNSSH_DEFAULT_PORT[ \t]+/ {
      print "#define HPNSSH_DEFAULT_PORT    22"
      next
    }
    { print }
  '
  grep -Eq '^#define[[:space:]]+HPNSSH_DEFAULT_PORT[[:space:]]+22$' "$ssh_h" ||
    die "Failed to set HPNSSH_DEFAULT_PORT to 22 in $ssh_h"

  if [[ -f "$sshd_config" ]]; then
    log "Setting sample hpnsshd_config Port to 22"
    rewrite_with_awk "$sshd_config" '
      $1 == "Port" && $2 == "2222" {
        print "Port 22"
        next
      }
      { print }
    '
  fi
}

patch_awslc_cipher_compat() {
  local src="$1"
  local ctr_mt_c="${src}/cipher-ctr-mt.c"
  local cipher_c="${src}/cipher.c"
  local chachapoly_mt_c="${src}/cipher-chachapoly-libcrypto-mt.c"

  log "Applying AWS-LC compatibility patch for AES-CTR-MT"
  [[ -f "$ctr_mt_c" ]] || die "Expected upstream cipher-ctr-mt.c not found: $ctr_mt_c"
  rewrite_with_awk "$ctr_mt_c" '
    /^#if defined\(WITH_OPENSSL\) && !defined\(WITH_OPENSSL3\)/ {
      print "#if defined(WITH_OPENSSL) && !defined(WITH_OPENSSL3) && !defined(HPNSSH_AWSLC)"
      next
    }
    { print }
  '

  [[ -f "$cipher_c" ]] || die "Expected upstream cipher.c not found: $cipher_c"
  rewrite_with_awk "$cipher_c" '
    /if \(strstr\(cc->cipher->name, "ctr"\) && enable_threads\) {/ {
      in_ctr_switch = 1
      print
      next
    }
    in_ctr_switch && /^[[:space:]]*#ifdef WITH_OPENSSL3/ {
      print "#if defined(HPNSSH_AWSLC)"
      print "\t\t\tdebug(\"AWS-LC lacks EVP_CIPHER_meth_*; using AWS-LC native AES-CTR\");"
      print "#elif defined(WITH_OPENSSL3)"
      in_ctr_switch = 0
      next
    }
    /^[[:space:]]*#if !defined\(WITH_OPENSSL3\)/ {
      print "#if !defined(WITH_OPENSSL3) && !defined(HPNSSH_AWSLC)"
      next
    }
    { print }
  '

  log "Disabling AWS-LC-incompatible ChaCha20-Poly1305-MT advertising"
  rewrite_with_awk "$cipher_c" '
    /^#ifdef WITH_OPENSSL$/ {
      pending_ifdef = 1
      pending_line = $0
      next
    }
    pending_ifdef && /"chacha20-poly1305-mt@hpnssh[.]org"/ {
      print "#ifndef HPNSSH_AWSLC"
      print pending_line
      print
      in_chacha_mt = 1
      pending_ifdef = 0
      next
    }
    pending_ifdef {
      print pending_line
      pending_ifdef = 0
    }
    in_chacha_mt {
      print
      if (/^[[:space:]]*#endif[[:space:]]*$/) {
        print "#endif"
        in_chacha_mt = 0
      }
      next
    }
    { print }
    END {
      if (pending_ifdef) {
        print pending_line
      }
    }
  '

  log "Adding AWS-LC stubs for unavailable ChaCha20-Poly1305-MT symbols"
  [[ -f "$chachapoly_mt_c" ]] || die "Expected upstream cipher-chachapoly-libcrypto-mt.c not found: $chachapoly_mt_c"
  rewrite_with_awk "$chachapoly_mt_c" '
    /^#if defined\(HAVE_EVP_CHACHA20\) && !defined\(HAVE_BROKEN_CHACHA20\)/ {
      print "#if defined(HPNSSH_AWSLC)"
      print ""
      print "#include \"cipher-chachapoly-libcrypto-mt.h\""
      print "#include \"ssherr.h\""
      print ""
      print "struct chachapoly_ctx_mt {"
      print "\tint disabled;"
      print "};"
      print ""
      print "struct chachapoly_ctx_mt *"
      print "chachapoly_new_mt(u_int startseqnr, const u_char *key, u_int keylen)"
      print "{"
      print "\t(void)startseqnr;"
      print "\t(void)key;"
      print "\t(void)keylen;"
      print "\treturn NULL;"
      print "}"
      print ""
      print "void"
      print "chachapoly_free_mt(struct chachapoly_ctx_mt *ctx_mt)"
      print "{"
      print "\t(void)ctx_mt;"
      print "}"
      print ""
      print "int"
      print "chachapoly_crypt_mt(struct chachapoly_ctx_mt *ctx_mt, u_int seqnr,"
      print "    u_char *dest, const u_char *src, u_int len, u_int aadlen,"
      print "    u_int authlen, int do_encrypt)"
      print "{"
      print "\t(void)ctx_mt;"
      print "\t(void)seqnr;"
      print "\t(void)dest;"
      print "\t(void)src;"
      print "\t(void)len;"
      print "\t(void)aadlen;"
      print "\t(void)authlen;"
      print "\t(void)do_encrypt;"
      print "\treturn SSH_ERR_INVALID_ARGUMENT;"
      print "}"
      print ""
      print "int"
      print "chachapoly_get_length_mt(struct chachapoly_ctx_mt *ctx_mt,"
      print "    u_int *plenp, u_int seqnr, const u_char *cp, u_int len)"
      print "{"
      print "\t(void)ctx_mt;"
      print "\t(void)plenp;"
      print "\t(void)seqnr;"
      print "\t(void)cp;"
      print "\t(void)len;"
      print "\treturn SSH_ERR_INVALID_ARGUMENT;"
      print "}"
      print ""
      print "#elif defined(HAVE_EVP_CHACHA20) && !defined(HAVE_BROKEN_CHACHA20)"
      next
    }
    { print }
  '

  grep -q 'defined(HPNSSH_AWSLC)' "$ctr_mt_c" ||
    die "Failed to patch cipher-ctr-mt.c for AWS-LC"
  grep -q 'AWS-LC native AES-CTR' "$cipher_c" ||
    die "Failed to patch cipher.c for AWS-LC"
  grep -q '#ifndef HPNSSH_AWSLC' "$cipher_c" ||
    die "Failed to disable ChaCha20-Poly1305-MT advertising for AWS-LC"
  grep -q '#if defined(HPNSSH_AWSLC)' "$chachapoly_mt_c" ||
    die "Failed to add ChaCha20-Poly1305-MT AWS-LC stubs"
}

write_config_site() {
  # Keep Autoconf probes anchored to the same SDK, Homebrew libraries, and
  # compiler/linker flags that are used for the final build.
  local config_site="${RUN_DIR}/config.site"
  cat > "$config_site" <<EOF
# Generated by build-hpnssh-macos-arm64.sh for this build only.
CPPFLAGS="${CPPFLAGS}"
LDFLAGS="${LDFLAGS}"
PKG_CONFIG_PATH="${PKG_CONFIG_PATH}"
EOF
  export CONFIG_SITE="$config_site"
  log "CONFIG_SITE: $CONFIG_SITE"
}

apply_macos_patches() {
  local src="$1"
  log "Applying macOS build normalization patch set"

  patch_version_marker "$src"
  patch_default_port "$src"

  if is_awslc_build; then
    patch_awslc_cipher_compat "$src"
  fi

  write_config_site

  if [[ -f "${src}/README.md" ]] && ! grep -q 'hpnssh' "${src}/README.md"; then
    warn "README.md did not contain hpnssh; upstream layout may have changed."
  fi
}

apply_macos_patches "$SRC_DIR"

cd "$SRC_DIR"
log "Bootstrapping configure with autoreconf -fi"
autoreconf -fi

CONFIGURE_ARGS=(
  "--prefix=${PREFIX}"
  "--exec-prefix=${PREFIX}"
  "--sysconfdir=${PREFIX}/etc"
  "--libexecdir=${PREFIX}/libexec"
  "--localstatedir=${PREFIX}/var"
  "--with-privsep-path=${PREFIX}/var/empty"
  "--with-pid-dir=${PREFIX}/var/run"
  "--with-ssl-dir=${CRYPTO_PREFIX}"
  "--with-zlib=${ZLIB_PREFIX}"
  "--with-pam"
  "--with-kerberos5=${KERBEROS_ROOT}"
)
if ((${#LIBEDIT_CONFIGURE_ARG[@]})); then
  CONFIGURE_ARGS+=("${LIBEDIT_CONFIGURE_ARG[@]}")
fi
if ((${#EXTRA_CONFIGURE_ARGS[@]})); then
  CONFIGURE_ARGS+=("${EXTRA_CONFIGURE_ARGS[@]}")
fi

log "Configuring HPN-SSH"
printf '  %q' ./configure "${CONFIGURE_ARGS[@]}"
printf '\n'
./configure "${CONFIGURE_ARGS[@]}"

log "Building with make -j${NCPU}"
make -j"${NCPU}"

strip_macho_binaries() {
  local src="$1"
  local stripped=0
  local candidate
  for candidate in "$src"/hpn*; do
    [[ -f "$candidate" && -x "$candidate" ]] || continue
    if file "$candidate" | grep -q 'Mach-O .*executable'; then
      log "Stripping debug symbols from $(basename "$candidate")"
      "$STRIP" -S "$candidate"
      log "Applying explicit ad-hoc code signature to $(basename "$candidate")"
      "$CODESIGN" --force --sign - "$candidate"
      stripped=$((stripped + 1))
    fi
  done
  [[ "$stripped" -gt 0 ]] || die "No Mach-O HPN binaries were found to strip."
  log "Stripped debug symbols from $stripped Mach-O binaries"
}

strip_macho_binaries "$SRC_DIR"

create_global_known_hosts_files() {
  local sysconf_dir="${PREFIX}/etc/hpnssh"
  local hostfile

  mkdir -p "$sysconf_dir"
  for hostfile in ssh_known_hosts ssh_known_hosts2; do
    if [[ ! -e "${sysconf_dir}/${hostfile}" ]]; then
      : > "${sysconf_dir}/${hostfile}"
      log "Created empty global host-key file: ${sysconf_dir}/${hostfile}"
    fi
    chmod 0644 "${sysconf_dir}/${hostfile}"
  done
}

if ((RUN_TESTS)); then
  log "Running make tests"
  make tests
fi

HPNSSH_BIN="${SRC_DIR}/hpnssh"
[[ -x "$HPNSSH_BIN" ]] || die "Built hpnssh binary not found: $HPNSSH_BIN"

VERSION_OUTPUT="$("$HPNSSH_BIN" -V 2>&1 || true)"
log "hpnssh -V: $VERSION_OUTPUT"
if [[ "$VERSION_OUTPUT" != *"$EXPECTED_HPN_SUFFIX"* ]]; then
  die "Validation failed: hpnssh -V did not contain ${EXPECTED_HPN_SUFFIX}"
fi
if [[ -n "$HPN_MARKER" && "$VERSION_OUTPUT" != *"$HPN_MARKER"* ]]; then
  die "Validation failed: hpnssh -V did not contain ${HPN_MARKER}"
fi

if ! file "$HPNSSH_BIN" | grep -q 'arm64'; then
  file "$HPNSSH_BIN" || true
  die "Validation failed: hpnssh binary is not reported as arm64"
fi
log "Binary architecture: $(file "$HPNSSH_BIN")"

require_linkage_contains "libcrypto" 'libcrypto' "${CRYPTO_PREFIX}/lib/libcrypto"
require_linkage_contains "libz" 'libz([.][0-9])?.*dylib' "$ZLIB_LINKAGE_EXPECTED"
reject_linkage "libbsm" 'libbsm'
require_linkage_contains "Kerberos" 'Kerberos[.]framework' "Kerberos.framework"
HPNSFTP_BIN="${SRC_DIR}/hpnsftp"
if [[ -x "$HPNSFTP_BIN" ]]; then
  if [[ -n "$LIBEDIT_LINKAGE_EXPECTED" ]]; then
    require_binary_linkage_contains "$HPNSFTP_BIN" "libedit" 'libedit([.][0-9])?.*dylib' "$LIBEDIT_LINKAGE_EXPECTED"
  else
    reject_binary_linkage "$HPNSFTP_BIN" "libedit" 'libedit([.][0-9])?.*dylib'
  fi
  if [[ "$LIBEDIT_MODE" == "system" ]]; then
    reject_binary_linkage "$HPNSFTP_BIN" "Homebrew libedit" '/opt/homebrew/.*/libedit'
  fi
fi

grep -q '^#define KRB5 1' "${SRC_DIR}/config.h" || die "Validation failed: KRB5 was not enabled in config.h"
grep -q '^#define GSSAPI 1' "${SRC_DIR}/config.h" || die "Validation failed: GSSAPI was not enabled in config.h"
log "Kerberos/GSSAPI config validation: KRB5 and GSSAPI enabled"

PORT_OUTPUT="$("$HPNSSH_BIN" -G localhost 2>/dev/null | awk '$1 == "port" { print $2; exit }')"
log "hpnssh default port: ${PORT_OUTPUT:-unknown}"
[[ "$PORT_OUTPUT" == "22" ]] || die "Validation failed: hpnssh default port is ${PORT_OUTPUT:-unknown}, expected 22"

if "$OTOOL" -l "$HPNSSH_BIN" | awk '/segname __DWARF/ { found=1 } END { exit found ? 0 : 1 }'; then
  die "Validation failed: hpnssh still contains __DWARF debug sections after strip."
fi
log "Debug section validation: no __DWARF sections found in hpnssh"

if ((INSTALL)); then
  log "Installing into isolated prefix: $PREFIX"
  make install
  create_global_known_hosts_files
  INSTALLED_BIN="${PREFIX}/bin/hpnssh"
  [[ -x "$INSTALLED_BIN" ]] || die "Installed hpnssh binary not found: $INSTALLED_BIN"
  INSTALLED_VERSION="$("$INSTALLED_BIN" -V 2>&1 || true)"
  log "Installed hpnssh -V: $INSTALLED_VERSION"
  [[ "$INSTALLED_VERSION" == *"$EXPECTED_HPN_SUFFIX"* ]] || die "Installed hpnssh validation failed: missing ${EXPECTED_HPN_SUFFIX}."
  [[ -z "$HPN_MARKER" || "$INSTALLED_VERSION" == *"$HPN_MARKER"* ]] || die "Installed hpnssh validation failed."
else
  log "Install not requested. Built binary remains at: $HPNSSH_BIN"
  log "Configured isolated install prefix remains: $PREFIX"
fi

log "HPN-SSH build completed successfully"
log "Build log: $LOG_FILE"
