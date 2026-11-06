# MacM2 HPN-SSH

Build scripts and documentation for isolated Apple Silicon builds of
[HPN-SSH](https://github.com/rapier1/hpn-ssh), using AWS-LC or OpenSSL with
macOS system zlib and libedit. Homebrew packages are maintained in the
separate [Homebrew tap](https://github.com/cecilyen/homebrew-hpnssh).

The repository name reflects the M2 Max validation host. Current source builds
target the M1 instruction baseline with M2 tuning and macOS 26.0 deployment.

## Current Source Builds

| Component | Version or setting |
| --- | --- |
| HPN-SSH | `18.12.1` |
| OpenSSH base | `10.6p2` |
| Crypto | AWS-LC `5.12.0` or OpenSSL `4.1.0` |
| Compiler | Homebrew LLVM `23.1.5` |
| Compression | macOS system zlib |
| Line editing | macOS system libedit |
| Security integration | PAM and Apple Kerberos; no BSM audit linkage |
| Platform | macOS 26 Tahoe, Apple Silicon `arm64` |
| Default client and server port | `22` |

The 2026-11-06 validation passed 869 unit tests per provider, 12 SSH
cipher/rekey checks, and four SFTP round trips. All 14 executables per variant
were stripped, signed, and checked. See [Building](docs/BUILDING.md) for
source provenance, validation details, and the OpenSSL AES-CTR-MT rekey
diagnostic observed during testing.

## Homebrew Distribution

Formulae, bottle versions, and runtime dependencies are maintained in the
[Homebrew tap](https://github.com/cecilyen/homebrew-hpnssh). Check its
[releases](https://github.com/cecilyen/homebrew-hpnssh/releases) for available
binaries and checksums; a source-build update here does not update a bottle.

## Install

```sh
brew tap cecilyen/hpnssh
brew install hpnssh-awslc
hpnssh -V
```

`hpnssh -V` reports the installed bottle's HPN-SSH and crypto-library versions.

Homebrew installs the `aws-lc` runtime dependency. zlib, libedit, PAM, and
Kerberos are supplied by macOS.

Installed commands keep their HPN names, including `hpnssh`, `hpnsshd`,
`hpnscp`, and `hpnsftp`. The formula does not overwrite `/usr/bin/ssh`,
`/usr/sbin/sshd`, or Homebrew OpenSSH.

The bottle creates configuration files under `/opt/homebrew/etc/hpnssh`. It
does not include host private keys, install a `launchd` service, or start a
daemon.

## Verify

```sh
hpnssh -V
hpnssh -F /dev/null -G localhost | sed -n '/^port /p'
otool -L "$(command -v hpnssh)"
otool -L "$(command -v hpnsftp)"
brew test hpnssh-awslc
```

Expected linkage includes Homebrew AWS-LC, `/usr/lib/libz.1.dylib`, and
Apple's Kerberos framework. `hpnsftp` also uses
`/usr/lib/libedit.3.dylib`.

## Build From Source

Install build dependencies:

```sh
brew install autoconf automake libtool llvm pkgconf aws-lc
```

Clone and build the current AWS-LC source profile:

```sh
git clone https://github.com/cecilyen/MacM2_hpn-ssh.git
cd MacM2_hpn-ssh
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh --tag hpn-18.12.1
```

The script leaves the build under `build-awslc-system-zlib/runs/` and writes
a timestamped log under `logs/`. It does not install by default. See
[Building](docs/BUILDING.md) for installation, test, and override options.

For OpenSSL, use
`scripts/build-hpnssh-macos-arm64-openssl-system-zlib.sh --tag hpn-18.12.1`.
It selects installed `openssl@4`, then `openssl@3`, and writes to
`build-openssl-system-zlib/runs/`.

Current local source defaults follow AGENTS.md:

```sh
CFLAGS="-O3 -arch arm64 -mcpu=apple-m1 -mtune=apple-m2 -flto=thin -pipe"
CXXFLAGS="-O3 -arch arm64 -mcpu=apple-m1 -mtune=apple-m2 -flto=thin -pipe"
LDFLAGS="-arch arm64 -mcpu=apple-m1 -mtune=apple-m2 -flto=thin -Wl,-dead_strip"
```

## Compatibility Notes

- AWS-LC is OpenSSL source compatible for this build, but it is not an
  ABI-compatible replacement for an existing OpenSSL-linked binary.
- HPN-SSH's custom AES-CTR-MT and ChaCha20-Poly1305-MT paths are disabled
  because AWS-LC does not provide the required legacy OpenSSL APIs. Standard
  AES-CTR, AES-GCM, and `chacha20-poly1305@openssh.com` remain available.
- PKCS#11 support is disabled in the validated AWS-LC build. Test hardware
  token workflows separately before migration.
- The HPN `none` cipher is never a safe choice on an untrusted network and is
  not selected by the default configuration.
- Running `hpnsshd` on port 22 can conflict with macOS Remote Login. Daemon
  deployment requires separate host keys, configuration, privileges, and any
  required organization approval.

## Documentation

- [System requirements](docs/SYSTEM_REQUIREMENTS.md)
- [Building](docs/BUILDING.md)
- [Build profiles](projects/README.md)
- [Optimization](docs/OPTIMIZATION.md)
- [Packaging](docs/PACKAGING.md)
- [Project layout and cleanup](docs/PROJECT_LAYOUT.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Crypto microbenchmark](benchmarks/crypto/README.md)

## Upstream Projects

- [HPN-SSH](https://github.com/rapier1/hpn-ssh)
- [OpenSSH portable](https://github.com/openssh/openssh-portable)
- [AWS-LC](https://github.com/aws/aws-lc)
- [Homebrew bottle documentation](https://docs.brew.sh/Bottles)
