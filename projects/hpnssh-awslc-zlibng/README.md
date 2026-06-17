# HPN-SSH AWS-LC + zlib-ng Fork

Main conclusion: this local fork builds HPN-SSH 18.9 against Homebrew AWS-LC
and Homebrew `zlib-ng-compat`, while keeping a separate build directory and
installation prefix from the OpenSSL and AWS-LC/zlib baselines.

## Build

```sh
chmod +x scripts/build-hpnssh-macos-arm64-awslc-zlibng.sh
scripts/build-hpnssh-macos-arm64-awslc-zlibng.sh
```

Defaults:

- Crypto provider: Homebrew `aws-lc`
- Compression provider: Homebrew `zlib-ng-compat`
- AWS-LC prefix: `/opt/homebrew/opt/aws-lc` when present
- zlib-ng compatibility prefix: `/opt/homebrew/opt/zlib-ng-compat` when present
- Build directory: `build-awslc-zlibng`
- Install prefix: `/opt/hpnssh-awslc-zlibng`
- Architecture: `arm64`
- Optimization: `-O3 -flto -g0 -mcpu=apple-m2` on this Apple M2 Max host
- Default HPN-SSH port: `22`

To install after a successful build:

```sh
sudo scripts/build-hpnssh-macos-arm64-awslc-zlibng.sh --install
```

## Validation

The wrapper delegates to the shared macOS builder, which validates:

- `hpnssh -V` contains the upstream HPN suffix, such as `_hpn18.9.0`
- The binary is Mach-O `arm64`
- `hpnssh` links `libcrypto` from the AWS-LC prefix
- `hpnssh` links `libz` from the `zlib-ng-compat` prefix
- `hpnssh` links Apple's Kerberos framework and does not link `libbsm`
- `hpnssh -G localhost` reports `port 22`
- The generated client has no `__DWARF` debug section after stripping

## Limitation

This fork uses `zlib-ng-compat`, not the native `zlib-ng` API. HPN-SSH consumes
the standard zlib API and links `libz`, so the compatibility package is the
correct Homebrew target for a drop-in zlib replacement.
