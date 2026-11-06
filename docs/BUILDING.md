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

## Build Current Source Profiles

The source wrappers currently select the latest tag in the `18.12` series.
Both use Homebrew LLVM and these local release defaults from AGENTS.md:

```sh
CFLAGS="-O3 -arch arm64 -mcpu=apple-m1 -mtune=apple-m2 -flto=thin -pipe"
CXXFLAGS="-O3 -arch arm64 -mcpu=apple-m1 -mtune=apple-m2 -flto=thin -pipe"
LDFLAGS="-arch arm64 -mcpu=apple-m1 -mtune=apple-m2 -flto=thin -Wl,-dead_strip"
```

Compile either provider from the same release:

```sh
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh --tag hpn-18.12.1
scripts/build-hpnssh-macos-arm64-openssl-system-zlib.sh --tag hpn-18.12.1
```

The OpenSSL wrapper prefers installed `openssl@4`, then `openssl@3`. Set
`HPNSSH_CRYPTO_FORMULA` and `HPNSSH_CRYPTO_PREFIX` to choose explicitly.
Upstream 18.12.1 accepts both OpenSSL 3 and 4. Missing dependencies stop the
build and print a separate installation command for review.

Both profiles use macOS system zlib and libedit, PAM, Kerberos, and port 22.
They strip debug symbols and apply ad-hoc signatures after linking. Outputs
remain in separate `build-awslc-system-zlib/runs/` and
`build-openssl-system-zlib/runs/` directories. These local source builds do
not update bottles; that publication workflow belongs to the separate tap.

## Reproduce The Published Profile

Use the exact release tag for a reproducible source selection:

```sh
HPNSSH_BASE_OPT_FLAGS="-O3 -arch arm64 -flto=thin -pipe" \
HPNSSH_BASE_LDFLAGS="-arch arm64 -flto=thin -Wl,-dead_strip" \
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh \
  --version-series 18.11 --tag hpn-18.11.1
```

Omit `--tag` to resolve the highest tag in the default `18.12` series:

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
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh --tag hpn-18.12.1
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
  --tag hpn-18.12.1 --run-tests
```

The 2026-11-06 local 18.12.1 validation passed 869 upstream unit tests per
provider, 12 SSH cipher/rekey checks across all four client/server pairings,
and four SFTP upload/download round trips. Transfer tests used 4 MiB payloads,
`curve25519-sha256`, and a forced 1 MiB rekey limit over a local pipe. Test
keys and payloads stayed under `/private/tmp` and were removed afterward.
All 14 executables per provider passed strict signature verification. The
full upstream regression target was not run for these local builds.

The OpenSSL AES-CTR-MT path logged `pthread_join failure: Invalid thread id`
at debug level during forced rekeying; byte comparisons still passed. This
upstream threading diagnostic remains unresolved. Validation details are in
`logs/hpnssh-18.12.1-validation-20261106.log` and the two provider unit logs.

The 18.11.1 release validation ran all executable non-privileged regressions
except the upstream `scp3` and `scp-resume` macOS harness cases, where
`/usr/bin/diff -r` encounters the suite's absolute symlink loop. The
`percent.sh` test used `/usr/bin/openssl` only to produce test-vector output in
the format expected by the harness; the shipped binaries remain linked to
AWS-LC. Unit, KEX, host-key, miscellaneous, formula, code-signature, and
cross-prefix bottle-pour checks passed.

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
CFLAGS="-O3 -arch arm64 -mcpu=apple-m1 -mtune=apple-m2 -flto=thin -pipe"
CXXFLAGS="-O3 -arch arm64 -mcpu=apple-m1 -mtune=apple-m2 -flto=thin -pipe"
LDFLAGS="-arch arm64 -mcpu=apple-m1 -mtune=apple-m2 -flto=thin -Wl,-dead_strip"
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
| `HPNSSH_CPU_TUNE` | Shared-builder `-mtune` target when base flags are not overridden |
| `HPNSSH_BASE_OPT_FLAGS` | C and C++ optimization flags |
| `HPNSSH_BASE_LDFLAGS` | Linker optimization flags |
| `CC`, `CXX`, `AR`, `RANLIB` | Compiler and archive tools |

See [Build profiles](../projects/README.md) before selecting a legacy
comparison wrapper.

## Source Provenance

The current local source builds use [upstream tag hpn-18.12.1](https://github.com/rapier1/hpn-ssh/tree/hpn-18.12.1),
based on OpenSSH 10.6p2, at commit:

```text
f2d16e85bf7c0026f5b360b9f97655d39a40fea6
```

The 2026-11-06 builds use AWS-LC 5.12.0 or OpenSSL 4.1.0 with Homebrew
LLVM 23.1.5 and a macOS 26.0 deployment target.

The published 18.11.1 build used upstream commit:

```text
f4cb96a30b1128a77737e5f1d00b4ec054633a42
```

The source archive SHA-256 is
`225238697414a73049770d87fab2453ab5871c1ae55c8853e4530ca5f2591239`.
The binary bottle checksum is listed in [Packaging](PACKAGING.md).
