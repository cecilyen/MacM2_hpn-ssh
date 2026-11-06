# Build Profiles

AWS-LC and OpenSSL source profiles share the current local release defaults.
The local 18.12.1 builds are validated here. Bottle versions and publication
are managed independently in the [Homebrew tap](https://github.com/cecilyen/homebrew-hpnssh).

| Status | Wrapper | Crypto | zlib / libedit | Direct-install prefix |
| --- | --- | --- | --- | --- |
| Supported | `build-hpnssh-macos-arm64-awslc-system-zlib.sh` | Homebrew AWS-LC | macOS / macOS | `/opt/hpnssh-awslc-system-zlib` |
| Supported source build | `build-hpnssh-macos-arm64-openssl-system-zlib.sh` | Homebrew OpenSSL 4, or 3 | macOS / macOS | `/opt/hpnssh-openssl-system-zlib` |
| Legacy comparison | `build-hpnssh-macos-arm64-awslc.sh` | Homebrew AWS-LC | Homebrew / Homebrew | `/opt/hpnssh-awslc` |
| Legacy comparison | `build-hpnssh-macos-arm64-awslc-zlibng.sh` | Homebrew AWS-LC | zlib-ng-compat / Homebrew | `/opt/hpnssh-awslc-zlibng` |
| Generic base | `build-hpnssh-macos-arm64.sh` | Homebrew OpenSSL 3 by default | Homebrew / Homebrew | `/opt/hpnssh` |

## Supported Profile

```sh
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh --tag hpn-18.12.1
scripts/build-hpnssh-macos-arm64-openssl-system-zlib.sh --tag hpn-18.12.1
```

The current local source profiles use:

- HPN-SSH `18.12.1`, based on OpenSSH `10.6p2`
- Homebrew AWS-LC `5.12.0` or OpenSSL `4.1.0`
- macOS system zlib and libedit
- PAM and Apple Kerberos/GSSAPI
- No BSM audit linkage
- ARM64 ThinLTO, M1 instruction baseline, and M2 tuning from AGENTS.md
- Port `22`
- Stripped and ad-hoc signed executables

The build validates linkage, architecture, version, port, Kerberos settings,
debug-section removal, and the absence of `libbsm`.

## Legacy Profiles

Legacy wrappers increase runtime dependencies and have not received the same
release validation as the supported profile. They remain useful for backend
and compression comparisons, but their output should not be described as the
published build.

Use separate work directories and prefixes when comparing profiles. Never
overlay one crypto provider's dylib with another provider; rebuild the client
against the intended library instead.

See [Building](../docs/BUILDING.md) and
[System requirements](../docs/SYSTEM_REQUIREMENTS.md) for the supported path.
