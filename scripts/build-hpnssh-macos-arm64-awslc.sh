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
export HPNSSH_PREFIX="${HPNSSH_PREFIX:-/opt/hpnssh-awslc}"
export HPNSSH_WORKDIR="${HPNSSH_WORKDIR:-${ROOT_DIR}/build-awslc}"
export HPNSSH_LOG_BASENAME="${HPNSSH_LOG_BASENAME:-hpnssh-awslc-build}"

exec "${ROOT_DIR}/scripts/build-hpnssh-macos-arm64.sh" "$@"
