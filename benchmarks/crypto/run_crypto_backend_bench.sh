#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
RESULT_DIR="${SCRIPT_DIR}/results"
SRC="${SCRIPT_DIR}/crypto_backend_bench.c"
BIN="${BUILD_DIR}/crypto_backend_bench"

mkdir -p "${BUILD_DIR}" "${RESULT_DIR}"

if [[ -x /opt/homebrew/opt/llvm/bin/clang ]]; then
  CC="${CC:-/opt/homebrew/opt/llvm/bin/clang}"
else
  CC="${CC:-/usr/bin/clang}"
fi

CFLAGS_DEFAULT="-O3 -arch arm64 -flto=thin -pipe -Wall -Wextra -Wpedantic"
LDFLAGS_DEFAULT="-arch arm64 -flto=thin -Wl,-dead_strip"

CFLAGS="${CFLAGS:-${CFLAGS_DEFAULT}}"
LDFLAGS="${LDFLAGS:-${LDFLAGS_DEFAULT}}"
BENCH_SECONDS="${BENCH_SECONDS:-1.0}"
BENCH_REPS="${BENCH_REPS:-5}"
BENCH_AES_MESSAGE_KIB="${BENCH_AES_MESSAGE_KIB:-1024}"

"${CC}" ${CFLAGS} "${SRC}" ${LDFLAGS} -o "${BIN}"

OUT="${RESULT_DIR}/aes256gcm-curve25519-libcrypto-$(date +%Y%m%d-%H%M%S).csv"
"${BIN}" \
  --seconds "${BENCH_SECONDS}" \
  --reps "${BENCH_REPS}" \
  --aes-message-kib "${BENCH_AES_MESSAGE_KIB}" \
  "$@" | tee "${OUT}"

printf 'wrote %s\n' "${OUT}" >&2
