# Building

Main conclusion: use the wrapper matching the library stack you want, and let
the shared builder resolve Homebrew paths, macOS Software Development Kit (SDK)
paths, compiler flags, and validation.

## Requirements

- macOS on Apple Silicon with Apple compiler tools available through `xcrun`.
- Homebrew packages for the selected variant:
  - Baseline: `openssl@3`, `zlib`, `autoconf`, `automake`, `libtool`, `libedit`.
  - AWS-LC: `aws-lc`, `zlib`, `autoconf`, `automake`, `libtool`, `libedit`.
  - AWS-LC + zlib-ng: `aws-lc`, `zlib-ng-compat`, `autoconf`, `automake`,
    `libtool`, `libedit`.

## Commands

```sh
scripts/build-hpnssh-macos-arm64.sh
scripts/build-hpnssh-macos-arm64-awslc.sh
scripts/build-hpnssh-macos-arm64-awslc-zlibng.sh
```

To build a fixed upstream tag:

```sh
scripts/build-hpnssh-macos-arm64-awslc-zlibng.sh --tag hpn-18.9.0
```

To install after a successful build:

```sh
sudo scripts/build-hpnssh-macos-arm64-awslc-zlibng.sh --install
```

## Important Environment Overrides

| Variable | Purpose |
| --- | --- |
| `HPNSSH_PREFIX` | Install prefix |
| `HPNSSH_WORKDIR` | Build workspace |
| `HPNSSH_TAG` | Explicit upstream tag |
| `HPNSSH_VERSION_SERIES` | Latest tag series, default `18.9` |
| `HPNSSH_CRYPTO_PREFIX` | Explicit crypto provider prefix |
| `ZLIB_PREFIX` | Explicit zlib-compatible provider prefix |
| `HPNSSH_CPU_TARGET` | Explicit Apple `-mcpu` target |

## What The Shared Builder Does

- Resolves the latest `hpn-18.9.x` tag unless an explicit tag is supplied.
- Clones a fresh source tree into the selected `build*/runs/` directory.
- Runs `autoreconf -fi`.
- Configures with PAM and Kerberos/GSSAPI support through Apple's Kerberos
  framework.
- Maps Homebrew crypto and compression headers/libraries into `CPPFLAGS`,
  `LDFLAGS`, and `PKG_CONFIG_PATH`.
- Forces `-arch arm64`, `-O3`, Link-Time Optimization (LTO), and `-g0`, then
  adds a detected Apple `-mcpu` target when available.
- Uses `sysctl -n hw.ncpu` for parallel `make`.
- Strips debug symbols and ad-hoc signs generated Mach-O executables.
- Validates architecture, dynamic library linkage, Kerberos support, default
  port `22`, and the upstream HPN version suffix.

## References

- Upstream HPN-SSH: <https://github.com/rapier1/hpn-ssh>
- Upstream OpenSSH portable: <https://github.com/openssh/openssh-portable>
