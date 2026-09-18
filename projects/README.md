# Build Profiles

One profile is supported for publication. The remaining wrappers are retained
only for controlled comparisons and are not published as bottles.

| Status | Wrapper | Crypto | zlib / libedit | Direct-install prefix |
| --- | --- | --- | --- | --- |
| Supported | `build-hpnssh-macos-arm64-awslc-system-zlib.sh` | Homebrew AWS-LC | macOS / macOS | `/opt/hpnssh-awslc-system-zlib` |
| Legacy comparison | `build-hpnssh-macos-arm64-awslc.sh` | Homebrew AWS-LC | Homebrew / Homebrew | `/opt/hpnssh-awslc` |
| Legacy comparison | `build-hpnssh-macos-arm64-awslc-zlibng.sh` | Homebrew AWS-LC | zlib-ng-compat / Homebrew | `/opt/hpnssh-awslc-zlibng` |
| Generic base | `build-hpnssh-macos-arm64.sh` | Homebrew OpenSSL 3 by default | Homebrew / Homebrew | `/opt/hpnssh` |

## Supported Profile

```sh
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh --tag hpn-18.11.1
```

This profile matches the published Homebrew formula:

- HPN-SSH `18.11.1`, based on OpenSSH `10.5p1`
- Homebrew AWS-LC, validated with `5.9.0`
- macOS system zlib and libedit
- PAM and Apple Kerberos/GSSAPI
- No BSM audit linkage
- ARM64 ThinLTO publication flags
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
