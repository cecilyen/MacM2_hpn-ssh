# System Requirements

The published binary archive targets macOS 26 on Apple Silicon `arm64` systems.
It is not an Intel macOS build, and it is not intended to replace Apple's system
OpenSSH.

## Supported Runtime Target

| Requirement | Supported value |
| --- | --- |
| Operating system | macOS 26 |
| CPU architecture | Apple Silicon `arm64` |
| Validated machine class | 2023 MacBook Pro with M2 Max and 32 GB memory |
| Homebrew prefix | `/opt/homebrew` |
| Install prefix | `/opt/hpnssh-awslc-system-zlib` |
| HPN-SSH default port | `22` |
| Crypto runtime | Homebrew `aws-lc` |
| Compression runtime | macOS `/usr/lib/libz.1.dylib` |
| Line-editing runtime | macOS `/usr/lib/libedit.3.dylib` for `hpnsftp` |

This project's release archive is narrower than the full set of Macs that may
be able to run macOS 26. Intel Macs are outside the supported binary target for
this repository because the packaged binaries are Mach-O `arm64` executables
and the runtime dependency path assumes Apple Silicon Homebrew.

## Minimum Runtime Dependencies

Install the only required Homebrew runtime library:

```sh
brew install aws-lc
```

The preferred AWS-LC + macOS zlib package does not require Homebrew `openssl@3`,
Homebrew `zlib`, Homebrew `zlib-ng`, or Homebrew `libedit` at runtime.

Expected system libraries and frameworks are provided by macOS 26:

- `/usr/lib/libSystem.B.dylib`
- `/usr/lib/libresolv.9.dylib`
- `/usr/lib/libz.1.dylib`
- `/usr/lib/libedit.3.dylib` for `hpnsftp`
- `/usr/lib/libncurses.5.4.dylib` for `hpnsftp`
- `/System/Library/Frameworks/Kerberos.framework`

## Build Host Requirements

To compile from source on macOS 26:

- Apple Silicon Mac with the macOS command line developer tools or Xcode
  toolchain available through `xcrun`.
- Homebrew installed under `/opt/homebrew`.
- Build dependencies:

```sh
brew install autoconf automake libtool aws-lc
```

The preferred build wrapper uses macOS SDK/system `zlib` and `libedit`, so
Homebrew `zlib` and Homebrew `libedit` are not required for that variant.

The local publication flags are:

```sh
CFLAGS="-O3 -arch arm64 -flto=thin -pipe"
CXXFLAGS="-O3 -arch arm64 -flto=thin -pipe"
LDFLAGS="-arch arm64 -flto=thin -Wl,-dead_strip"
```

These flags are intentionally generic for M1-and-newer Apple Silicon rather
than tuned only for M2 Max.

## Operational Notes

- Keep the HPN-SSH installation isolated under `/opt/hpnssh-awslc-system-zlib`
  or another dedicated prefix.
- Do not overwrite `/usr/bin/ssh`, `/usr/sbin/sshd`, `/opt/homebrew/bin/ssh`,
  or stock OpenSSH configuration files.
- Running `hpnsshd` on privileged port `22` can conflict with Apple's system
  SSH service and may require administrator and organization approval.
- If a copied binary is killed by macOS with `SIGKILL`, ad-hoc sign the final
  copied file with `codesign --force --sign - /path/to/hpnssh`.
- The build is configured without `libbsm`; Kerberos/GSSAPI support uses
  Apple's Kerberos framework.

## Verification Commands

```sh
/opt/hpnssh-awslc-system-zlib/bin/hpnssh -V
/opt/hpnssh-awslc-system-zlib/bin/hpnssh -G localhost | grep '^port '
otool -L /opt/hpnssh-awslc-system-zlib/bin/hpnssh
otool -L /opt/hpnssh-awslc-system-zlib/bin/hpnsftp
```

Expected results:

- `hpnssh -V` reports `OpenSSH_10.3p1_hpn18.9.0, AWS-LC 5.1.0`.
- `hpnssh` links Homebrew AWS-LC and macOS `/usr/lib/libz.1.dylib`.
- `hpnsftp` links macOS `/usr/lib/libedit.3.dylib`.
- No HPN executable links Homebrew `libedit`, Homebrew `zlib-ng-compat`, or
  `libbsm`.

## References

- Apple macOS information and compatibility entry point: <https://www.apple.com/os/macos/>
- Homebrew AWS-LC formula: <https://formulae.brew.sh/formula/aws-lc>
- AWS-LC upstream: <https://github.com/aws/aws-lc>
- HPN-SSH upstream: <https://github.com/rapier1/hpn-ssh>
