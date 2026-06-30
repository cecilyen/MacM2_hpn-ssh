# HPN-SSH AWS-LC Fork

This legacy variant builds HPN-SSH 18.9 against Homebrew AWS-LC with Homebrew
zlib. It keeps a separate build directory and installation prefix from the
published AWS-LC + macOS zlib build.

## Build

```sh
chmod +x scripts/build-hpnssh-macos-arm64-awslc.sh
scripts/build-hpnssh-macos-arm64-awslc.sh
```

Defaults:

- Crypto provider: Homebrew `aws-lc`
- AWS-LC prefix: `/opt/homebrew/opt/aws-lc` when present
- Build directory: `build-awslc`
- Install prefix: `/opt/hpnssh-awslc`
- Architecture: `arm64`
- Optimization: local full-LTO profile from the shared builder
- Default HPN-SSH port: `22`

To install after a successful build:

```sh
sudo scripts/build-hpnssh-macos-arm64-awslc.sh --install
```

## Validation

The wrapper delegates to the shared macOS builder, which validates:

- `hpnssh -V` contains the upstream HPN suffix, such as `_hpn18.9.0`
- The binary is Mach-O `arm64`
- `hpnssh` links `libcrypto` from the AWS-LC prefix
- `hpnssh` links Apple's Kerberos framework and does not link `libbsm`
- `hpnssh -G localhost` reports `port 22`
- The generated client has no `__DWARF` debug section after stripping

## Limitations

AWS-LC is Application Programming Interface (API) compatible with much of
OpenSSL, but it is not Application Binary Interface (ABI) stable. Do not swap it
under an existing OpenSSL-linked HPN-SSH binary; rebuild HPN-SSH against AWS-LC.

This HPN-SSH source disables Public-Key Cryptography Standards #11 (PKCS#11)
when AWS-LC is detected. Validate smart-card, hardware-token, and security-key
workflows before treating this build as a replacement for the OpenSSL build.

AWS-LC does not expose the `EVP_CIPHER_meth_*` APIs used by HPN-SSH's
pre-OpenSSL-3 custom AES-CTR-MT hook. The AWS-LC wrapper patches that hook out
for AWS-LC builds, so AES-CTR uses AWS-LC's native AES-CTR implementation.

AWS-LC also does not expose the `EVP_chacha20` API required by HPN-SSH's
`chacha20-poly1305-mt@hpnssh.org` hook. This fork does not advertise that
multithreaded cipher under AWS-LC. The standard
`chacha20-poly1305@openssh.com` cipher remains available.

## Known Hosts

If `hpnssh -v` reports missing global host-key files, create empty placeholders:

```sh
sudo mkdir -p /opt/hpnssh-awslc/etc/hpnssh
sudo touch /opt/hpnssh-awslc/etc/hpnssh/ssh_known_hosts /opt/hpnssh-awslc/etc/hpnssh/ssh_known_hosts2
sudo chmod 0644 /opt/hpnssh-awslc/etc/hpnssh/ssh_known_hosts /opt/hpnssh-awslc/etc/hpnssh/ssh_known_hosts2
```

This removes the debug noise without changing normal per-user host-key checking
in `~/.ssh/known_hosts`.
