# MacM2 HPN-SSH

Main conclusion: this repository builds and packages isolated HPN-SSH 18.9
clients and daemons for Apple Silicon macOS, tuned for an M2 Max system, without
replacing Apple's system OpenSSH binaries.

The build automation downloads HPN-SSH from the official
[rapier1/hpn-ssh](https://github.com/rapier1/hpn-ssh) repository, configures it
for macOS, compiles `arm64` binaries, and keeps the upstream `hpn` command names
such as `hpnssh`, `hpnsshd`, `hpnscp`, and `hpnsftp`.

## Current Build

The current uploaded binary build is:

- HPN-SSH: `18.9.0`
- OpenSSH base: `10.3p1`
- Crypto: AWS-LC `5.0.0`
- Compression: Homebrew `zlib-ng-compat`
- Architecture: `arm64`
- macOS target used for this project: macOS 26 on Apple Silicon
- Default client port: `22`
- Install prefix used by the AWS-LC + zlib-ng build:
  `/opt/hpnssh-awslc-zlibng`

Homebrew formulae are intentionally not published in this repository yet.

## Install From GitHub Release

Install the minimal Homebrew runtime libraries first:

```sh
brew install aws-lc zlib-ng-compat libedit
```

Those are the only Homebrew packages required to run all binaries in the current
AWS-LC + zlib-ng release archive. The packaged tools also link macOS-provided
system libraries and frameworks such as Kerberos, PAM, libresolv, libSystem,
libsandbox, and system ncurses.

Runtime linkage checked from the release archive:

| Binary set | Homebrew runtime libraries |
| --- | --- |
| `hpnssh`, `hpnscp`, `hpnssh-add`, `hpnssh-agent`, `hpnssh-keygen`, `hpnssh-keyscan`, `hpnssh-keysign`, `hpnssh-pkcs11-helper`, `hpnssh-sk-helper`, `hpnsshd`, `hpnsshd-auth`, `hpnsshd-session` | `aws-lc`, `zlib-ng-compat` |
| `hpnsftp` | `libedit` |
| `hpnsftp-server` | none from Homebrew |

Download the release archive from this repository's GitHub Releases page, then:

```sh
mkdir -p /tmp/machpnssh
tar -xzf hpnssh-awslc-zlibng-hpnssh-18.9.0-macos26-arm64.tar.gz -C /tmp/machpnssh

sudo mkdir -p /opt/hpnssh-awslc-zlibng
sudo cp -R /tmp/machpnssh/hpnssh-awslc-zlibng/bin /opt/hpnssh-awslc-zlibng/
sudo codesign --force --sign - /opt/hpnssh-awslc-zlibng/bin/hpnssh

/opt/hpnssh-awslc-zlibng/bin/hpnssh -V
otool -L /opt/hpnssh-awslc-zlibng/bin/hpnssh
```

If you want the tools on your shell path:

```sh
mkdir -p "$HOME/bin"
ln -sf /opt/hpnssh-awslc-zlibng/bin/hpnssh "$HOME/bin/hpnssh"
ln -sf /opt/hpnssh-awslc-zlibng/bin/hpnscp "$HOME/bin/hpnscp"
ln -sf /opt/hpnssh-awslc-zlibng/bin/hpnsftp "$HOME/bin/hpnsftp"
```

If macOS terminates a copied binary with `SIGKILL`, ad-hoc sign the final copy:

```sh
codesign --force --sign - "$HOME/bin/hpnssh"
```

## Compile From Source

Install build dependencies:

```sh
brew install autoconf automake libtool libedit aws-lc zlib-ng-compat
```

The build dependencies are broader than the runtime set because compiling from
source requires Autoconf, Automake, and Libtool. Running the released binaries
does not require those build tools.

Clone this repository:

```sh
git clone https://github.com/cecilyen/MacM2_hpn-ssh.git
cd MacM2_hpn-ssh
```

Build the preferred AWS-LC + zlib-ng variant:

```sh
scripts/build-hpnssh-macos-arm64-awslc-zlibng.sh --tag hpn-18.9.0
```

The script writes a fresh source/build tree under `build-awslc-zlibng/runs/` and
a timestamped log under `logs/`. It does not install by default.

Install after a successful build:

```sh
sudo scripts/build-hpnssh-macos-arm64-awslc-zlibng.sh --tag hpn-18.9.0 --install
```

Verify the installed client:

```sh
/opt/hpnssh-awslc-zlibng/bin/hpnssh -V
/opt/hpnssh-awslc-zlibng/bin/hpnssh -G localhost | grep '^port '
otool -L /opt/hpnssh-awslc-zlibng/bin/hpnssh
```

Expected version output includes:

```text
OpenSSH_10.3p1_hpn18.9.0, AWS-LC 5.0.0
```

## Other Build Variants

The shared build script also supports OpenSSL 3 and AWS-LC with standard zlib:

```sh
scripts/build-hpnssh-macos-arm64.sh --tag hpn-18.9.0
scripts/build-hpnssh-macos-arm64-awslc.sh --tag hpn-18.9.0
```

The current prebuilt GitHub Release only includes the AWS-LC + zlib-ng archive.
Older local OpenSSL and AWS-LC-only build outputs were not uploaded because they
failed current release validation.

## Build Behavior

The build scripts:

- Resolve Homebrew paths dynamically.
- Map AWS-LC/OpenSSL and zlib/zlib-ng headers and libraries into compiler and
  linker flags.
- Use `xcrun --show-sdk-path` for macOS Software Development Kit (SDK) paths.
- Compile `arm64` with `-O3`, Link-Time Optimization (LTO), `-g0`, and a
  detected Apple `-mcpu` target.
- Run `autoreconf -fi`.
- Configure Pluggable Authentication Modules (PAM) and Kerberos/GSSAPI support
  through Apple's Kerberos framework.
- Patch HPN's default client port back to `22`.
- Strip debug symbols and ad-hoc sign generated Mach-O executables.
- Validate `hpnssh -V`, architecture, linked libraries, default port, Kerberos,
  and absence of `libbsm`.

## Package A GitHub Release

Generate release-ready archives from the latest validated local build outputs:

```sh
scripts/package-github-release.sh
```

The output appears under:

```text
release/hpnssh-18.9.0-macos26-arm64/
```

Upload the generated `*.tar.gz`, `SHA256SUMS`, `MANIFEST.txt`, `SKIPPED.txt`,
and `RELEASE_NOTES.md` files to a GitHub Release.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `scripts/` | Build, cleanup, and release packaging scripts |
| `docs/` | Detailed build, optimization, troubleshooting, packaging, and layout notes |
| `projects/` | Variant-specific notes |
| `build*/`, `logs/`, `profiles/`, `release/` | Generated local artifacts ignored by Git |

## Limitations

- These binaries target Apple Silicon `arm64`, not Intel macOS.
- AWS-LC is Application Programming Interface (API) compatible with much of
  OpenSSL, but it is not an Application Binary Interface (ABI) stable drop-in
  library replacement.
- The scripts compile HPN-SSH but do not create production host keys, a
  `launchd` service, or a site authentication policy.
- Compiler flags can help local throughput, but network latency, cipher choice,
  compression, congestion control, storage, and the remote host also affect SSH
  performance.

## References

- HPN-SSH upstream: <https://github.com/rapier1/hpn-ssh>
- OpenSSH portable upstream: <https://github.com/openssh/openssh-portable>
- AWS-LC: <https://github.com/aws/aws-lc>
