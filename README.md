# MacM2 HPN-SSH

Build scripts and release documentation for an isolated Apple Silicon build of
[HPN-SSH](https://github.com/rapier1/hpn-ssh). The supported package is a
macOS 26 ARM64 Homebrew bottle linked to AWS-LC. It does not replace Apple's
OpenSSH or Homebrew OpenSSH.

The repository name reflects the M2 Max validation host. The release uses
generic ARM64 flags and is intended for M1 and newer Apple Silicon systems
running macOS 26.

## Current Release

| Component | Version or setting |
| --- | --- |
| HPN-SSH | `18.11.0` |
| OpenSSH base | `10.5p1` |
| Crypto | Homebrew AWS-LC, validated with `5.9.0` |
| Compression | macOS system zlib |
| Line editing | macOS system libedit |
| Security integration | PAM and Apple Kerberos; no BSM audit linkage |
| Platform | macOS 26 Tahoe, Apple Silicon `arm64` |
| Default client and server port | `22` |

Release formula and binaries:

- [Homebrew tap](https://github.com/cecilyen/homebrew-hpnssh)
- [HPN-SSH 18.11.0 bottle release](https://github.com/cecilyen/homebrew-hpnssh/releases/tag/hpnssh-awslc-18.11.0-macos26-arm64)

## Install

```sh
brew tap cecilyen/hpnssh
brew install hpnssh-awslc
hpnssh -V
```

Expected output:

```text
OpenSSH_10.5p1_hpn18.11.0, AWS-LC 5.9.0
```

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

Clone and build the published profile:

```sh
git clone https://github.com/cecilyen/MacM2_hpn-ssh.git
cd MacM2_hpn-ssh
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh --tag hpn-18.11.0
```

The script leaves the build under `build-awslc-system-zlib/runs/` and writes
a timestamped log under `logs/`. It does not install by default. See
[Building](docs/BUILDING.md) for installation, test, and override options.

The release profile uses:

```sh
CFLAGS="-O3 -arch arm64 -flto=thin -pipe"
CXXFLAGS="-O3 -arch arm64 -flto=thin -pipe"
LDFLAGS="-arch arm64 -flto=thin -Wl,-dead_strip"
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
