# Pure libcrypto Benchmark

This microbenchmark compares crypto-library primitives relevant to SSH on
Apple Silicon. It is independent of the HPN-SSH bottle and does not represent
the package's configured cipher or KEX defaults.

Measured primitives:

- AES-256-GCM encryption and authenticated decryption
- X25519 shared-secret derivation plus SHA-256

Default library paths:

| Backend | Library |
| --- | --- |
| Homebrew AWS-LC | `/opt/homebrew/opt/aws-lc/lib/libcrypto.dylib` |
| Homebrew OpenSSL 3 | `/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib` |
| macOS LibreSSL | `/usr/lib/libcrypto.46.dylib` |

The benchmark avoids compile-time OpenSSL headers. It uses `dlopen(3)` and
`dlsym(3)` so one executable can load the three providers without header or
linker conflicts. All listed libraries must be available unless the executable
is invoked with its backend-selection option.

## Build And Run

```sh
./benchmarks/crypto/run_crypto_backend_bench.sh
```

Useful controls:

```sh
BENCH_SECONDS=2.0 BENCH_REPS=7 BENCH_AES_MESSAGE_KIB=1024 \
  ./benchmarks/crypto/run_crypto_backend_bench.sh
```

The wrapper prefers `/opt/homebrew/opt/llvm/bin/clang` and compiles with the
same generic ARM64 ThinLTO profile used by the published HPN-SSH build:

```sh
CFLAGS="-O3 -arch arm64 -flto=thin -pipe"
LDFLAGS="-arch arm64 -flto=thin -Wl,-dead_strip"
```

Timestamped CSV results are written under
`benchmarks/crypto/results/`, which is ignored by Git.

## Measured Operations

`aes256-gcm-encrypt-evp`

: EVP AES-256-GCM encryption of fixed-size messages. The default message is
  1024 KiB.

`aes256-gcm-decrypt-evp`

: EVP AES-256-GCM decryption with authentication-tag verification.

`curve25519-sha256-evp-freshctx`

: X25519 derivation plus SHA-256 with a new EVP derive context for every
  operation. This is closer to handshake-style use.

`curve25519-sha256-evp-reusedctx`

: X25519 derivation plus SHA-256 with an initialized derive context reused
  across operations. This is closer to a primitive lower bound.

## Interpretation Limits

- This is not an SSH client/server benchmark. It excludes packet framing,
  sockets, authentication, disk I/O, scheduling, and the remote endpoint.
- `curve25519-sha256` here means X25519 derivation followed by SHA-256 over the
  32-byte shared secret. A real OpenSSH exchange hash includes transcript
  fields and protocol processing.
- The EVP API gives a comparable public interface, but it does not guarantee
  identical provider-internal code paths.
- Results from short runs are sensitive to thermal state, CPU scheduling, and
  background activity. Use repeated runs and report the raw CSV files.
