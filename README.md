# MacM2 HPN-SSH

This repository builds isolated HPN-SSH for Apple Silicon macOS without
replacing Apple's system OpenSSH. The current published package is a Homebrew
bottle built with AWS-LC.

## Current Release

- HPN-SSH: `18.11.0`
- OpenSSH base: `10.5p1`
- Crypto: Homebrew AWS-LC `5.9.0`
- Compression: macOS system `zlib`
- Line editing: macOS system `libedit`
- Security integration: PAM and Apple's Kerberos framework; no `libbsm`
- Architecture and OS: Apple Silicon `arm64`, macOS 26 Tahoe
- Default client and server port: `22`
- Build flags:
  `CFLAGS="-O3 -arch arm64 -flto=thin -pipe"`
  `CXXFLAGS="-O3 -arch arm64 -flto=thin -pipe"`
  `LDFLAGS="-arch arm64 -flto=thin -Wl,-dead_strip"`

## Install With Homebrew

```sh
brew tap cecilyen/hpnssh
brew install hpnssh-awslc
hpnssh -V
```

Expected version output:

```text
OpenSSH_10.5p1_hpn18.11.0, AWS-LC 5.9.0
```

Homebrew installs AWS-LC automatically. zlib, libedit, PAM, and Kerberos come
from macOS, so they are not Homebrew runtime dependencies.

The tap and bottle are published at:

- [cecilyen/homebrew-hpnssh](https://github.com/cecilyen/homebrew-hpnssh)
- [HPN-SSH 18.11.0 AWS-LC bottle](https://github.com/cecilyen/homebrew-hpnssh/releases/tag/hpnssh-awslc-18.11.0-macos26-arm64)

The installed commands retain the upstream HPN names: `hpnssh`, `hpnsshd`,
`hpnscp`, `hpnsftp`, and related helpers. They do not overwrite
`/usr/bin/ssh`, `/usr/sbin/sshd`, or Homebrew OpenSSH.

Homebrew configuration paths:

- Client: `/opt/homebrew/etc/hpnssh/ssh_config`
- Server: `/opt/homebrew/etc/hpnssh/sshd_config`
- Global known hosts: `/opt/homebrew/etc/hpnssh/ssh_known_hosts{,2}`

The bottle does not contain host private keys and does not install or start a
`launchd` service.

## Verify

```sh
hpnssh -V
hpnssh -F /dev/null -G localhost | grep '^port '
otool -L "$(command -v hpnssh)"
otool -L "$(command -v hpnsftp)"
brew test hpnssh-awslc
```

Expected runtime linkage includes Homebrew AWS-LC, macOS system zlib, and
Apple's Kerberos framework. `hpnsftp` also links macOS system libedit.

## Compile From Source

Install build dependencies:

```sh
brew install autoconf automake libtool llvm pkgconf aws-lc
```

Clone this repository:

```sh
git clone https://github.com/cecilyen/MacM2_hpn-ssh.git
cd MacM2_hpn-ssh
```

Build the preferred AWS-LC plus macOS zlib/libedit variant:

```sh
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh --tag hpn-18.11.0
```

The script writes a fresh source tree under
`build-awslc-system-zlib/runs/` and a timestamped log under `logs/`. It
does not install by default.

To install into the isolated direct-build prefix after a successful build:

```sh
sudo scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh \
  --tag hpn-18.11.0 --install
```

The direct-build prefix is `/opt/hpnssh-awslc-system-zlib`. Administrative
installation and daemon deployment may require organization approval.

## Build Behavior

The preferred builder:

- Resolves the latest official `hpn-18.11.x` tag.
- Resolves Homebrew dependency paths dynamically.
- Uses the macOS SDK path reported by `xcrun --show-sdk-path`.
- Runs `autoreconf -fi`.
- Compiles ARM64 with generic M1-and-newer ThinLTO flags.
- Uses `sysctl -n hw.ncpu` for parallel compilation.
- Configures PAM and Kerberos/GSSAPI through Apple's Kerberos framework.
- Uses macOS SDK/system zlib and libedit.
- Patches the HPN default port to `22`.
- Applies the macOS SDK 27 sandbox declaration compatibility patch.
- Disables AWS-LC-incompatible HPN AES-CTR-MT and
  ChaCha20-Poly1305-MT paths while retaining standard AES-CTR, AES-GCM, and
  `chacha20-poly1305@openssh.com`.
- Strips debug symbols and ad-hoc signs each Mach-O executable.
- Validates version, architecture, port, linkage, Kerberos, and absence of
  `libbsm`.

## Other Variants

The shared builder also supports OpenSSL 3, AWS-LC with Homebrew zlib, and
AWS-LC with zlib-ng-compat:

```sh
scripts/build-hpnssh-macos-arm64.sh --tag hpn-18.11.0
scripts/build-hpnssh-macos-arm64-awslc.sh --tag hpn-18.11.0
scripts/build-hpnssh-macos-arm64-awslc-zlibng.sh --tag hpn-18.11.0
```

These variants are retained for comparison and local testing. The published
Homebrew bottle uses AWS-LC plus macOS zlib/libedit to minimize runtime
dependencies.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `scripts/` | Build, cleanup, benchmark, and direct-archive scripts |
| `docs/` | System requirements, build, optimization, and packaging notes |
| `projects/` | Variant-specific build profiles |
| `homebrew-tap/` | Ignored local checkout of the separate Homebrew tap repository |
| `build*/`, `logs/`, `release/`, `dist/` | Generated artifacts ignored by Git |

## Limitations

- The published bottle targets macOS 26 on Apple Silicon, not Intel macOS.
- AWS-LC is source-compatible with much of OpenSSL but is not an ABI-stable
  drop-in replacement.
- Running `hpnsshd` on port 22 can conflict with macOS Remote Login.
- Compiler flags do not remove network, storage, remote-host, or protocol
  bottlenecks.

## Documentation

- [System requirements](docs/SYSTEM_REQUIREMENTS.md)
- [Building](docs/BUILDING.md)
- [Optimization](docs/OPTIMIZATION.md)
- [Packaging](docs/PACKAGING.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

## References

- [HPN-SSH upstream](https://github.com/rapier1/hpn-ssh)
- [OpenSSH portable upstream](https://github.com/openssh/openssh-portable)
- [AWS-LC upstream](https://github.com/aws/aws-lc)
- [Homebrew bottle documentation](https://docs.brew.sh/Bottles)
