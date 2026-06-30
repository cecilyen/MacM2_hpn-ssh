# Pure libcrypto Benchmark

This microbenchmark compares the crypto primitives relevant to the fixed SSH
profile:

- Cipher: `aes256-gcm`
- KEX primitive: `curve25519-sha256`

It compares these installed backends:

- Homebrew AWS-LC: `/opt/homebrew/opt/aws-lc/lib/libcrypto.dylib`
- Homebrew OpenSSL 3: `/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib`
- macOS LibreSSL: `/usr/lib/libcrypto.46.dylib`

The benchmark intentionally avoids compile-time OpenSSL headers. It uses
`dlopen(3)` and `dlsym(3)` so the same binary can load AWS-LC, OpenSSL, and the
system LibreSSL dylib without header conflicts.

## Build And Run

```sh
./benchmarks/crypto/run_crypto_backend_bench.sh
```

Useful knobs:

```sh
BENCH_SECONDS=2.0 BENCH_REPS=7 BENCH_AES_MESSAGE_KIB=1024 \
  ./benchmarks/crypto/run_crypto_backend_bench.sh
```

The wrapper prefers `/opt/homebrew/opt/llvm/bin/clang` and compiles with:

```sh
CFLAGS="-O3 -arch arm64 -flto=thin -pipe"
LDFLAGS="-arch arm64 -flto=thin -Wl,-dead_strip"
```

Results are written as timestamped CSV files under:

```text
benchmarks/crypto/results/
```

## Measured Operations

`aes256-gcm-encrypt-evp`

: EVP AES-256-GCM encryption of fixed-size messages. Default message size is
  1024 KiB.

`aes256-gcm-decrypt-evp`

: EVP AES-256-GCM decryption with tag verification of fixed-size messages.

`curve25519-sha256-evp-freshctx`

: X25519 shared-secret derivation plus SHA256, creating a fresh EVP derive
  context for each operation. This is closer to handshake-style use.

`curve25519-sha256-evp-reusedctx`

: X25519 shared-secret derivation plus SHA256 while reusing an initialized EVP
  derive context. This is closer to the primitive lower bound.

## Limits

- This is a primitive libcrypto benchmark, not an SSH benchmark.
- `curve25519-sha256` here means X25519 derive plus SHA256 over the 32-byte
  shared secret. OpenSSH's real exchange hash includes additional transcript
  fields.
- The test uses EVP APIs for comparability. It does not benchmark private
  library internals or OpenSSH's own non-libcrypto code paths.
- macOS may provide system LibreSSL as a dyld-shared-cache library even when a
  matching physical file is not visible under `/usr/lib`.
