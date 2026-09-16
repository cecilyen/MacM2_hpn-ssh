# Building

Use the wrapper matching the library stack you want. The shared builder resolves
Homebrew paths, the macOS SDK, compiler flags, source patches, and validation.

## Requirements

- macOS 26 on Apple Silicon `arm64`.
- Command line developer tools or Xcode available through `xcrun`.
- Homebrew under `/opt/homebrew`.

Preferred AWS-LC plus macOS zlib/libedit build:

```sh
brew install autoconf automake libtool llvm pkgconf aws-lc
```

Other variants may also need `openssl@3`, `zlib`, `libedit`, or
`zlib-ng-compat`.

## Commands

```sh
scripts/build-hpnssh-macos-arm64.sh
scripts/build-hpnssh-macos-arm64-awslc.sh
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh
scripts/build-hpnssh-macos-arm64-awslc-zlibng.sh
```

Build the current fixed upstream tag:

```sh
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh --tag hpn-18.11.0
```

The build remains under `build-awslc-system-zlib/runs/` unless `--install`
is supplied. Direct installation uses the isolated
`/opt/hpnssh-awslc-system-zlib` prefix:

```sh
sudo scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh \
  --tag hpn-18.11.0 --install
```

## Environment Overrides

| Variable | Purpose |
| --- | --- |
| `HPNSSH_PREFIX` | Isolated direct-install prefix |
| `HPNSSH_WORKDIR` | Build workspace |
| `HPNSSH_TAG` | Explicit upstream tag |
| `HPNSSH_VERSION_SERIES` | Latest tag series; default `18.11` |
| `HPNSSH_CRYPTO_PREFIX` | Explicit crypto-provider prefix |
| `ZLIB_PREFIX` | Explicit zlib-compatible provider prefix |
| `HPNSSH_ZLIB_MODE` | `homebrew` or `system` |
| `HPNSSH_LIBEDIT_MODE` | `homebrew`, `system`, or `disabled` |
| `HPNSSH_CPU_TARGET` | Explicit Apple `-mcpu` target |
| `HPNSSH_BASE_OPT_FLAGS` | Override C/C++ optimization flags |
| `HPNSSH_BASE_LDFLAGS` | Override linker optimization flags |
| `CC`, `CXX`, `AR`, `RANLIB` | Override the compiler and archive tools |

## Shared Builder Behavior

- Resolves the latest official `hpn-18.11.x` tag unless a tag is supplied.
- Clones a fresh source tree into the selected `build*/runs/` directory.
- Runs `autoreconf -fi`.
- Uses the SDK reported by `xcrun --show-sdk-path`.
- Configures PAM and Kerberos/GSSAPI through Apple's Kerberos framework.
- Supports Homebrew or macOS SDK/system zlib and libedit.
- Uses `sysctl -n hw.ncpu` for parallel `make`.
- Forces `arm64`; the preferred wrapper uses:

```sh
CFLAGS="-O3 -arch arm64 -flto=thin -pipe"
CXXFLAGS="-O3 -arch arm64 -flto=thin -pipe"
LDFLAGS="-arch arm64 -flto=thin -Wl,-dead_strip"
```

- Uses LLVM `llvm-ar` and `llvm-ranlib` with Homebrew LLVM so ThinLTO
  archives remain readable.
- Patches the default HPN port to `22`.
- Applies the macOS SDK 27 sandbox declaration compatibility patch.
- Disables AWS-LC-incompatible AES-CTR-MT and ChaCha20-Poly1305-MT paths.
- Strips and ad-hoc signs generated Mach-O executables.
- Validates version, architecture, linkage, Kerberos, system zlib/libedit,
  port `22`, and absence of `libbsm`.

## Published Bottle

The Homebrew formula and bottle are maintained separately:

```sh
brew tap cecilyen/hpnssh
brew install hpnssh-awslc
```

See [cecilyen/homebrew-hpnssh](https://github.com/cecilyen/homebrew-hpnssh).

## References

- [HPN-SSH upstream](https://github.com/rapier1/hpn-ssh)
- [OpenSSH portable upstream](https://github.com/openssh/openssh-portable)
