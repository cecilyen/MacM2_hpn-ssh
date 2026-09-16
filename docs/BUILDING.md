# Building

The supported source profile builds HPN-SSH with Homebrew AWS-LC and macOS
system zlib, libedit, PAM, and Kerberos. The build remains isolated from both
Apple OpenSSH and Homebrew OpenSSH.

## Requirements

- macOS 26 on Apple Silicon `arm64`
- Xcode or Command Line Tools available through `xcrun`
- A writable Homebrew installation under the standard `/opt/homebrew` prefix
- Git and network access to the official HPN-SSH repository

Install the build dependencies:

```sh
brew install autoconf automake libtool llvm pkgconf aws-lc
```

The preferred wrapper uses Homebrew LLVM for the compiler, archiver, and
indexer. Using matching `llvm-ar` and `llvm-ranlib` is required for ThinLTO
archives.

## Build The Published Profile

Use the exact release tag for a reproducible source selection:

```sh
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh --tag hpn-18.11.0
```

Omit `--tag` to resolve the highest tag in the configured `18.11` series:

```sh
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh
```

Each run receives a new directory under:

```text
build-awslc-system-zlib/runs/hpn-<version>-<timestamp>/hpn-ssh/
```

The log is written under `logs/`. Building does not modify `/opt` and does not
need administrator privileges.

## Install A Direct Build

Do not run the build wrapper itself with `sudo`; it invokes Homebrew and should
create its source tree as the current user. Build first, then elevate only the
install target for the configured `/opt/hpnssh-awslc-system-zlib` prefix:

```sh
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh --tag hpn-18.11.0
sudo make -C build-awslc-system-zlib/runs/<run>/hpn-ssh install-nokeys
```

`install-nokeys` deliberately omits server host private keys. The wrapper's
`--install` option is appropriate only when `HPNSSH_PREFIX` names a location
that the current user may write; upstream `make install` can create host keys.

Direct installation is separate from the Homebrew formula. Review
administrative and organization policy before writing to `/opt` or deploying
`hpnsshd`. For most users, the published Homebrew bottle is simpler.

## Tests And Validation

Run the upstream test target explicitly:

```sh
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh \
  --tag hpn-18.11.0 --run-tests
```

The full regression suite can stop in the recursive SCP test on macOS when
`/usr/bin/diff -r` encounters the suite's absolute symlink loop. This is a
test-harness interaction, not evidence that a failed transfer should be
ignored. The release build was separately validated with the unit/KEX tests,
functional key scanning, formula tests, code-signature checks, and a relocated
bottle pour.

Every normal build validates:

- HPN-SSH version suffix and AWS-LC identity
- Mach-O `arm64` architecture
- AWS-LC, system zlib, system libedit, and Kerberos linkage
- PAM and Kerberos/GSSAPI configuration
- Absence of `libbsm` and Homebrew libedit linkage
- Default port `22`
- Removal of `__DWARF` sections
- Application of ad-hoc signatures after stripping

## Release Flags

```sh
CFLAGS="-O3 -arch arm64 -flto=thin -pipe"
CXXFLAGS="-O3 -arch arm64 -flto=thin -pipe"
LDFLAGS="-arch arm64 -flto=thin -Wl,-dead_strip"
```

The wrapper also reads the SDK path from `xcrun`, runs `autoreconf -fi`, and
uses `sysctl -n hw.ncpu` for parallel `make`.

## Environment Overrides

| Variable | Purpose |
| --- | --- |
| `HPNSSH_PREFIX` | Isolated direct-install prefix |
| `HPNSSH_WORKDIR` | Build workspace |
| `HPNSSH_TAG` | Explicit upstream tag |
| `HPNSSH_VERSION_SERIES` | Tag series used for latest-tag resolution |
| `HPNSSH_CRYPTO_PREFIX` | Explicit crypto-provider prefix |
| `ZLIB_PREFIX` | Explicit zlib-compatible provider prefix |
| `HPNSSH_ZLIB_MODE` | `homebrew` or `system` |
| `HPNSSH_LIBEDIT_MODE` | `homebrew`, `system`, or `disabled` |
| `HPNSSH_CPU_TARGET` | Shared-builder `-mcpu` target when base flags are not overridden |
| `HPNSSH_BASE_OPT_FLAGS` | C and C++ optimization flags |
| `HPNSSH_BASE_LDFLAGS` | Linker optimization flags |
| `CC`, `CXX`, `AR`, `RANLIB` | Compiler and archive tools |

See [Build profiles](../projects/README.md) before selecting a legacy
comparison wrapper.

## Source Provenance

The published 18.11.0 build used upstream commit:

```text
1bd56196268fe2e23ed7c9b344b76f38d77a2fd3
```

The formula records the source archive checksum. The binary bottle checksum is
listed in [Packaging](PACKAGING.md).
