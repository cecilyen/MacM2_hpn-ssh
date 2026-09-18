# System Requirements

The published bottle is a macOS 26 Tahoe, Apple Silicon `arm64` package. It is
not an Intel build and does not replace Apple's system OpenSSH.

## Supported Runtime

| Requirement | Supported value |
| --- | --- |
| Operating system | macOS 26 Tahoe |
| CPU architecture | Apple Silicon `arm64` |
| Validated host | 2023 MacBook Pro, M2 Max, 32 GB, macOS 26.6.2 |
| Homebrew prefix | `/opt/homebrew` |
| Formula | `cecilyen/hpnssh/hpnssh-awslc` |
| HPN-SSH | `18.11.1`, based on OpenSSH `10.5p1` |
| Crypto | Homebrew `aws-lc`, validated with `5.9.0` |
| Compression | macOS `/usr/lib/libz.1.dylib` |
| Line editing | macOS `/usr/lib/libedit.3.dylib` for `hpnsftp` |
| Default port | `22` |

Install with:

```sh
brew tap cecilyen/hpnssh
brew install hpnssh-awslc
```

AWS-LC is the only Homebrew runtime dependency and is installed
automatically. Homebrew OpenSSL, zlib, zlib-ng-compat, and libedit are not
runtime requirements for this bottle.

macOS supplies libSystem, libresolv, zlib, libedit, PAM, the Darwin sandbox
libraries, and the Kerberos framework.

## Installed Paths

| Item | Path |
| --- | --- |
| Client commands | `/opt/homebrew/bin/hpnssh`, `hpnscp`, `hpnsftp`, and helpers |
| Server command | `/opt/homebrew/sbin/hpnsshd` |
| Client configuration | `/opt/homebrew/etc/hpnssh/ssh_config` |
| Server configuration | `/opt/homebrew/etc/hpnssh/sshd_config` |
| Global known hosts | `/opt/homebrew/etc/hpnssh/ssh_known_hosts` and `ssh_known_hosts2` |
| Formula keg | `/opt/homebrew/Cellar/hpnssh-awslc/18.11.1` |

The formula uses `install-nokeys`. No host private keys are embedded in the
bottle, and no daemon or `launchd` service is installed or started.

## Source Build Host

Source compilation additionally requires:

- Xcode or Command Line Tools available through `xcrun`
- Homebrew LLVM and build tools
- Network access to the official HPN-SSH repository

```sh
brew install autoconf automake libtool llvm pkgconf aws-lc
```

The release was built with Homebrew Clang 23.1.1 and macOS SDK 27.0. The
formula and wrapper discover their active SDK and Homebrew prefixes instead of
hard-coding the Cellar version paths.

## Functional Limits

- The formula enables PAM and Apple Kerberos/GSSAPI but not BSM audit linkage.
- PKCS#11 is disabled in the validated AWS-LC configuration.
- HPN-SSH's custom AES-CTR-MT and ChaCha20-Poly1305-MT paths are disabled for
  AWS-LC. Standard AES-CTR, AES-GCM, and
  `chacha20-poly1305@openssh.com` remain.
- The generic ARM64 flags target M1 and newer processors; the bottle does not
  require M2-specific instructions.
- Running `hpnsshd` on port 22 can conflict with macOS Remote Login and may
  require administrator and organization approval.

## Verify

```sh
hpnssh -V
hpnssh -F /dev/null -G localhost | sed -n '/^port /p'
otool -L "$(command -v hpnssh)"
otool -L "$(command -v hpnsftp)"
brew test hpnssh-awslc
```

Expected version:

```text
OpenSSH_10.5p1_hpn18.11.1, AWS-LC 5.9.0
```

## References

- [Homebrew AWS-LC formula](https://formulae.brew.sh/formula/aws-lc)
- [AWS-LC](https://github.com/aws/aws-lc)
- [HPN-SSH](https://github.com/rapier1/hpn-ssh)
