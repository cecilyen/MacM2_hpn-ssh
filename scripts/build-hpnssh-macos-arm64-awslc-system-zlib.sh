#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

detect_awslc_prefix() {
  if [[ -n "${HPNSSH_CRYPTO_PREFIX:-}" ]]; then
    printf '%s\n' "$HPNSSH_CRYPTO_PREFIX"
    return 0
  fi

  local brew_bin="${BREW_BIN:-$(command -v brew || true)}"
  if [[ -n "$brew_bin" ]]; then
    local homebrew_prefix
    homebrew_prefix="$("$brew_bin" --prefix 2>/dev/null || true)"
    if [[ -n "$homebrew_prefix" && -d "${homebrew_prefix}/opt/aws-lc" ]]; then
      printf '%s\n' "${homebrew_prefix}/opt/aws-lc"
      return 0
    fi
  fi

  if [[ -d /opt/homebrew/opt/aws-lc ]]; then
    printf '%s\n' /opt/homebrew/opt/aws-lc
    return 0
  fi

  printf '%s\n' aws-lc
}

export HPNSSH_CRYPTO_NAME="${HPNSSH_CRYPTO_NAME:-AWS-LC}"
export HPNSSH_CRYPTO_FORMULA="${HPNSSH_CRYPTO_FORMULA:-aws-lc}"
export HPNSSH_CRYPTO_PREFIX="$(detect_awslc_prefix)"
export HPNSSH_ZLIB_MODE=system
export HPNSSH_LIBEDIT_MODE=system
export ZLIB_PREFIX="${ZLIB_PREFIX:-/usr}"
export HPNSSH_PREFIX="${HPNSSH_PREFIX:-/opt/hpnssh-awslc-system-zlib}"
export HPNSSH_WORKDIR="${HPNSSH_WORKDIR:-${ROOT_DIR}/build-awslc-system-zlib}"
export HPNSSH_LOG_BASENAME="${HPNSSH_LOG_BASENAME:-hpnssh-awslc-system-zlib-build}"
export HPNSSH_BASE_OPT_FLAGS="${HPNSSH_BASE_OPT_FLAGS:--O3 -arch arm64 -flto=thin -pipe}"
export HPNSSH_BASE_LDFLAGS="${HPNSSH_BASE_LDFLAGS:--arch arm64 -flto=thin -Wl,-dead_strip}"

if [[ -x /opt/homebrew/opt/llvm/bin/clang ]]; then
  export CC="${CC:-/opt/homebrew/opt/llvm/bin/clang}"
  export CXX="${CXX:-/opt/homebrew/opt/llvm/bin/clang++}"
  export AR="${AR:-/opt/homebrew/opt/llvm/bin/llvm-ar}"
  export RANLIB="${RANLIB:-/opt/homebrew/opt/llvm/bin/llvm-ranlib}"
fi

exec "${ROOT_DIR}/scripts/build-hpnssh-macos-arm64.sh" "$@"
