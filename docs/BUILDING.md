# Building

Use the wrapper matching the library stack you want. The shared builder resolves
Homebrew paths, macOS Software Development Kit (SDK) paths, compiler flags, and
validation.

## Requirements

- macOS 26 on Apple Silicon `arm64` with Apple compiler tools available
  through `xcrun`. See `docs/SYSTEM_REQUIREMENTS.md` for the runtime and build
  host assumptions used for the published archive.
- Homebrew packages for the selected variant:
  - Baseline: `openssl@3`, `zlib`, `autoconf`, `automake`, `libtool`, `libedit`.
  - AWS-LC: `aws-lc`, `zlib`, `autoconf`, `automake`, `libtool`, `libedit`.
  - AWS-LC + macOS zlib: `aws-lc`, `autoconf`, `automake`, `libtool`,
    using macOS SDK/system `zlib` and `libedit`.
  - AWS-LC + zlib-ng: `aws-lc`, `zlib-ng-compat`, `autoconf`, `automake`,
    `libtool`, `libedit`.

The AWS-LC + macOS zlib wrapper is the published build profile. The other
wrappers are retained for comparison and local testing.

## Commands

```sh
scripts/build-hpnssh-macos-arm64.sh
scripts/build-hpnssh-macos-arm64-awslc.sh
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh
scripts/build-hpnssh-macos-arm64-awslc-zlibng.sh
```

To build a fixed upstream tag:

```sh
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh --tag hpn-18.9.0
```

To install after a successful build:

```sh
sudo scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh --install
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
| `HPNSSH_ZLIB_MODE` | `homebrew` or `system`; the AWS-LC system-zlib wrapper sets `system` |
| `HPNSSH_LIBEDIT_MODE` | `homebrew`, `system`, or `disabled`; the AWS-LC system-zlib wrapper sets `system` |
| `HPNSSH_CPU_TARGET` | Explicit Apple `-mcpu` target |
| `HPNSSH_BASE_OPT_FLAGS` | Override base `CFLAGS`/`CXXFLAGS` optimization flags |
| `HPNSSH_BASE_LDFLAGS` | Override base linker optimization flags |

## What The Shared Builder Does

- Resolves the latest `hpn-18.9.x` tag unless an explicit tag is supplied.
- Clones a fresh source tree into the selected `build*/runs/` directory.
- Runs `autoreconf -fi`.
- Configures with PAM and Kerberos/GSSAPI support through Apple's Kerberos
  framework.
- Maps crypto and selected compression headers/libraries into `CPPFLAGS`,
  `LDFLAGS`, and `PKG_CONFIG_PATH`.
- Supports Homebrew or macOS SDK/system `libedit`; the preferred AWS-LC +
  macOS zlib wrapper validates that `hpnsftp` links `/usr/lib/libedit.3.dylib`.
- Forces `-arch arm64`; the default builder adds `-O3`, Link-Time Optimization
  (LTO), `-g0`, and a detected Apple `-mcpu` target, while the
  AWS-LC + macOS zlib wrapper uses generic ThinLTO flags:
  `-O3 -arch arm64 -flto=thin -pipe` and
  `-arch arm64 -flto=thin -Wl,-dead_strip`.
- Uses `sysctl -n hw.ncpu` for parallel `make`.
- Strips debug symbols and ad-hoc signs generated Mach-O executables.
- Validates architecture, dynamic library linkage, Kerberos support, default
  port `22`, and the upstream HPN version suffix.

## References

- Upstream HPN-SSH: <https://github.com/rapier1/hpn-ssh>
- Upstream OpenSSH portable: <https://github.com/openssh/openssh-portable>
