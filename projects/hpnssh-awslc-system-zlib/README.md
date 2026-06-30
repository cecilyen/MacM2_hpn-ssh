# HPN-SSH AWS-LC + macOS zlib Fork

This is the published build profile. It builds HPN-SSH 18.9 against Homebrew
AWS-LC 5.1.x while using macOS system `zlib` and `libedit`, reducing Homebrew
runtime dependencies compared with the zlib-ng build.

## Build

```sh
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh --tag hpn-18.9.0
```

Defaults:

- Crypto provider: Homebrew `aws-lc`
- Compression provider: macOS system `zlib`
- Line-editing provider: macOS system `libedit`
- AWS-LC prefix: `/opt/homebrew/opt/aws-lc` when present
- zlib linkage: `/usr/lib/libz.1.dylib`
- libedit linkage: `/usr/lib/libedit.3.dylib`
- Build directory: `build-awslc-system-zlib`
- Install prefix: `/opt/hpnssh-awslc-system-zlib`
- Architecture: `arm64`
- Optimization:
  `-O3 -arch arm64 -flto=thin -pipe`
  and `-arch arm64 -flto=thin -Wl,-dead_strip`
- Default HPN-SSH port: `22`

To install after a successful build:

```sh
sudo scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh --install
```

## Validation

The wrapper delegates to the shared macOS builder, which validates:

- `hpnssh -V` contains the upstream HPN suffix, such as `_hpn18.9.0`
- The version output reports AWS-LC, for example `AWS-LC 5.1.0`
- The binary is Mach-O `arm64`
- `hpnssh` links `libcrypto` from the AWS-LC prefix
- `hpnssh` links macOS `/usr/lib/libz.1.dylib`
- `hpnsftp` links macOS `/usr/lib/libedit.3.dylib`
- `hpnssh` links Apple's Kerberos framework and does not link `libbsm`
- `hpnssh -G localhost` reports `port 22`
- The generated client has no `__DWARF` debug section after stripping

## Runtime Dependencies

This variant targets macOS 26 on Apple Silicon `arm64` systems. The root
`docs/SYSTEM_REQUIREMENTS.md` file lists the full runtime and build host
requirements.

Install only the Homebrew runtime libraries not provided by macOS:

```sh
brew install aws-lc
```

Most binaries need Homebrew `aws-lc` plus macOS system libraries. `hpnsftp`
uses macOS system `libedit`, and `hpnsftp-server` has no Homebrew runtime
dependency in this variant.
