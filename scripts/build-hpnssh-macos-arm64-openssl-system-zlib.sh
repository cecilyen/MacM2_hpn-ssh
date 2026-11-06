#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BREW_BIN="${BREW_BIN:-$(command -v brew)}"
HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-$("$BREW_BIN" --prefix)}"

if [[ -z "${HPNSSH_CRYPTO_FORMULA:-}" ]]; then
  if [[ -d "${HOMEBREW_PREFIX}/opt/openssl@4" ]]; then
    HPNSSH_CRYPTO_FORMULA=openssl@4
  else
    HPNSSH_CRYPTO_FORMULA=openssl@3
  fi
fi

export HPNSSH_CRYPTO_NAME="${HPNSSH_CRYPTO_NAME:-OpenSSL}"
export HPNSSH_CRYPTO_FORMULA
export HPNSSH_CRYPTO_PREFIX="${HPNSSH_CRYPTO_PREFIX:-${HOMEBREW_PREFIX}/opt/${HPNSSH_CRYPTO_FORMULA}}"
export HPNSSH_ZLIB_MODE=system
export HPNSSH_LIBEDIT_MODE=system
export ZLIB_PREFIX="${ZLIB_PREFIX:-/usr}"
export HPNSSH_PREFIX="${HPNSSH_PREFIX:-/opt/hpnssh-openssl-system-zlib}"
export HPNSSH_WORKDIR="${HPNSSH_WORKDIR:-${ROOT_DIR}/build-openssl-system-zlib}"
export HPNSSH_LOG_BASENAME="${HPNSSH_LOG_BASENAME:-hpnssh-openssl-system-zlib-build}"

exec "${ROOT_DIR}/scripts/build-hpnssh-macos-arm64.sh" "$@"
