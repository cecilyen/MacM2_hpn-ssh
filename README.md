# MacM2 HPN-SSH

This repository builds and packages isolated HPN-SSH 18.9 clients and daemons
for Apple Silicon macOS without replacing Apple's system OpenSSH binaries.

The build automation downloads HPN-SSH from the official
[rapier1/hpn-ssh](https://github.com/rapier1/hpn-ssh) repository, configures it
for macOS, compiles `arm64` binaries, and keeps the upstream `hpn` command names
such as `hpnssh`, `hpnsshd`, `hpnscp`, and `hpnsftp`.

## Current Published Build

The current published build is:

- HPN-SSH: `18.9.0`
- OpenSSH base: `10.3p1`
- Crypto: Homebrew AWS-LC `5.1.0`
- Compression: macOS system `zlib`
- Architecture: `arm64`
- macOS target: macOS 26 on Apple Silicon
- Default client port: `22`
- Build flags:
  `CFLAGS="-O3 -arch arm64 -flto=thin -pipe"`
  `CXXFLAGS="-O3 -arch arm64 -flto=thin -pipe"`
  `LDFLAGS="-arch arm64 -flto=thin -Wl,-dead_strip"`
- Install prefix: `/opt/hpnssh-awslc-system-zlib`

## Install From GitHub Release

System requirements are documented in
[`docs/SYSTEM_REQUIREMENTS.md`](docs/SYSTEM_REQUIREMENTS.md). In short, the
published archive targets macOS 26 on Apple Silicon `arm64` systems and uses
Homebrew AWS-LC as its only Homebrew runtime library.

Install the minimal Homebrew runtime libraries first:

```sh
brew install aws-lc
```

This is the only Homebrew package required to run all binaries in the
AWS-LC + macOS zlib archive. The packaged tools also link macOS-provided system
libraries and frameworks such as Kerberos, PAM, libresolv, libSystem, libz,
libedit, libsandbox, and system ncurses.

Runtime linkage checked from the published build:

| Binary set | Homebrew runtime libraries |
| --- | --- |
| `hpnssh`, `hpnscp`, `hpnssh-add`, `hpnssh-agent`, `hpnssh-keygen`, `hpnssh-keyscan`, `hpnssh-keysign`, `hpnssh-pkcs11-helper`, `hpnssh-sk-helper`, `hpnsshd`, `hpnsshd-auth`, `hpnsshd-session` | `aws-lc` |
| `hpnsftp` | none from Homebrew |
| `hpnsftp-server` | none from Homebrew |

Download the preferred release archive from this repository's GitHub Releases
page, then:

```sh
mkdir -p /tmp/machpnssh
tar -xzf hpnssh-awslc-system-zlib-hpnssh-18.9.0-macos26-arm64.tar.gz -C /tmp/machpnssh

sudo mkdir -p /opt/hpnssh-awslc-system-zlib
sudo cp -R /tmp/machpnssh/hpnssh-awslc-system-zlib/bin /opt/hpnssh-awslc-system-zlib/
sudo codesign --force --sign - /opt/hpnssh-awslc-system-zlib/bin/hpnssh

/opt/hpnssh-awslc-system-zlib/bin/hpnssh -V
otool -L /opt/hpnssh-awslc-system-zlib/bin/hpnssh
```

If you want the tools on your shell path:

```sh
mkdir -p "$HOME/bin"
ln -sf /opt/hpnssh-awslc-system-zlib/bin/hpnssh "$HOME/bin/hpnssh"
ln -sf /opt/hpnssh-awslc-system-zlib/bin/hpnscp "$HOME/bin/hpnscp"
ln -sf /opt/hpnssh-awslc-system-zlib/bin/hpnsftp "$HOME/bin/hpnsftp"
```

If macOS terminates a copied binary with `SIGKILL`, ad-hoc sign the final copy:

```sh
codesign --force --sign - "$HOME/bin/hpnssh"
```

## Compile From Source

Install build dependencies:

```sh
brew install autoconf automake libtool aws-lc
```

The build dependencies are broader than the runtime set because compiling from
source requires Autoconf, Automake, and Libtool. Running the released binaries
does not require those build tools.

Clone this repository:

```sh
git clone https://github.com/cecilyen/MacM2_hpn-ssh.git
cd MacM2_hpn-ssh
```

Build the preferred AWS-LC + macOS zlib variant:

```sh
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh --tag hpn-18.9.0
```

The script writes a fresh source/build tree under
`build-awslc-system-zlib/runs/` and a timestamped log under `logs/`. It does
not install by default.

Install after a successful build:

```sh
sudo scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh --tag hpn-18.9.0 --install
```

Verify the installed client:

```sh
/opt/hpnssh-awslc-system-zlib/bin/hpnssh -V
/opt/hpnssh-awslc-system-zlib/bin/hpnssh -G localhost | grep '^port '
otool -L /opt/hpnssh-awslc-system-zlib/bin/hpnssh
```

Expected version output includes:

```text
OpenSSH_10.3p1_hpn18.9.0, AWS-LC 5.1.0
```

## Other Build Variants

The shared build script also supports OpenSSL 3, AWS-LC with Homebrew zlib, and
AWS-LC with zlib-ng-compat:

```sh
scripts/build-hpnssh-macos-arm64.sh --tag hpn-18.9.0
scripts/build-hpnssh-macos-arm64-awslc.sh --tag hpn-18.9.0
scripts/build-hpnssh-macos-arm64-awslc-zlibng.sh --tag hpn-18.9.0
```

Those variants are retained for comparison and local experiments. The AWS-LC +
macOS zlib variant is the preferred published build because it requires fewer
Homebrew runtime libraries than the zlib-ng variant while still using AWS-LC
for `libcrypto`.

## Build Behavior

The build scripts:

- Resolve Homebrew paths dynamically.
- Map AWS-LC/OpenSSL and selected zlib-compatible headers and libraries into
  compiler and linker flags.
- Use `xcrun --show-sdk-path` for macOS Software Development Kit (SDK) paths.
- Use macOS SDK/system `zlib` and `libedit` in the preferred AWS-LC build.
- Compile `arm64`; the AWS-LC + macOS zlib wrapper uses generic ThinLTO flags
  for M1-and-newer Apple Silicon compatibility.
- Run `autoreconf -fi`.
- Configure Pluggable Authentication Modules (PAM) and Kerberos/GSSAPI support
  through Apple's Kerberos framework.
- Patch HPN's default client port back to `22`.
- Strip debug symbols and ad-hoc sign generated Mach-O executables.
- Validate `hpnssh -V`, architecture, linked libraries, default port, Kerberos,
  and absence of `libbsm`.

## Package A GitHub Release

Generate release-ready archives from the latest local build outputs:

```sh
scripts/package-github-release.sh
```

The output appears under:

```text
release/hpnssh-18.9.0-macos26-arm64/
```

Upload the generated `*.tar.gz`, `SHA256SUMS`, `MANIFEST.txt`, `SKIPPED.txt`,
and `RELEASE_NOTES.md` files as GitHub Release assets.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `scripts/` | Build, cleanup, and release packaging scripts |
| `docs/` | Detailed system requirements, build, optimization, troubleshooting, packaging, and layout notes |
| `projects/` | Variant-specific build profiles |
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
