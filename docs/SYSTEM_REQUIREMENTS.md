# System Requirements

The published Homebrew bottle targets macOS 26 Tahoe on Apple Silicon
`arm64`. It is not an Intel build and does not replace Apple's system
OpenSSH.

## Supported Runtime

| Requirement | Supported value |
| --- | --- |
| Operating system | macOS 26 Tahoe |
| CPU architecture | Apple Silicon `arm64` |
| Validated machine | 2023 MacBook Pro, M2 Max, 32 GB |
| Homebrew prefix | `/opt/homebrew` |
| Formula | `cecilyen/hpnssh/hpnssh-awslc` |
| HPN-SSH | `18.11.0`, based on OpenSSH `10.5p1` |
| Default port | `22` |
| Crypto | Homebrew AWS-LC `5.9.0` at build time |
| Compression | macOS `/usr/lib/libz.1.dylib` |
| Line editing | macOS `/usr/lib/libedit.3.dylib` for `hpnsftp` |

## Install

```sh
brew tap cecilyen/hpnssh
brew install hpnssh-awslc
```

AWS-LC is the only Homebrew runtime dependency and is installed
automatically. The bottle does not require Homebrew OpenSSL, zlib,
zlib-ng-compat, or libedit.

macOS provides:

- `/usr/lib/libSystem.B.dylib`
- `/usr/lib/libresolv.9.dylib`
- `/usr/lib/libz.1.dylib`
- `/usr/lib/libedit.3.dylib`
- `/System/Library/Frameworks/Kerberos.framework`
- PAM and the Darwin sandbox libraries

## Paths

| Item | Path |
| --- | --- |
| Commands | `/opt/homebrew/bin/hpn*` and `/opt/homebrew/sbin/hpnsshd` |
| Client configuration | `/opt/homebrew/etc/hpnssh/ssh_config` |
| Server configuration | `/opt/homebrew/etc/hpnssh/sshd_config` |
| Global known hosts | `/opt/homebrew/etc/hpnssh/ssh_known_hosts{,2}` |
| Formula keg | `/opt/homebrew/Cellar/hpnssh-awslc/18.11.0` |

The bottle contains no host private keys and does not install a `launchd`
service.

## Build Host

Source compilation requires:

- macOS 26 on Apple Silicon
- Command line developer tools or Xcode through `xcrun`
- Homebrew under `/opt/homebrew`
- These build packages:

```sh
brew install autoconf automake libtool llvm pkgconf aws-lc
```

The preferred flags are:

```sh
CFLAGS="-O3 -arch arm64 -flto=thin -pipe"
CXXFLAGS="-O3 -arch arm64 -flto=thin -pipe"
LDFLAGS="-arch arm64 -flto=thin -Wl,-dead_strip"
```

These flags are generic for M1-and-newer Apple Silicon, not only M2 Max.

## Operational Limits

- Running `hpnsshd` on port 22 can conflict with macOS Remote Login and may
  require administrator and organization approval.
- The formula uses PAM and Apple's Kerberos framework but not `libbsm`.
- AWS-LC builds disable HPN-SSH's custom AES-CTR-MT and
  ChaCha20-Poly1305-MT paths because AWS-LC lacks their required legacy
  OpenSSL APIs.
- Standard AES-CTR, AES-GCM, and `chacha20-poly1305@openssh.com` remain.

## Verify

```sh
hpnssh -V
hpnssh -F /dev/null -G localhost | grep '^port '
otool -L "$(command -v hpnssh)"
otool -L "$(command -v hpnsftp)"
brew test hpnssh-awslc
```

Expected version:

```text
OpenSSH_10.5p1_hpn18.11.0, AWS-LC 5.9.0
```

## References

- [Homebrew AWS-LC formula](https://formulae.brew.sh/formula/aws-lc)
- [AWS-LC upstream](https://github.com/aws/aws-lc)
- [HPN-SSH upstream](https://github.com/rapier1/hpn-ssh)
