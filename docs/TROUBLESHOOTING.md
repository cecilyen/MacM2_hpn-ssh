# Troubleshooting

Start by identifying which installation you are running:

```sh
command -v hpnssh
hpnssh -V
otool -L "$(command -v hpnssh)"
codesign --verify --verbose=2 "$(command -v hpnssh)"
```

The Homebrew bottle normally resolves to `/opt/homebrew/bin/hpnssh`. A manual
source installation normally resolves under
`/opt/hpnssh-awslc-system-zlib/bin`.

## A Copied Binary Is Killed By macOS

Use the Homebrew-installed binary when possible. If a build-tree executable
works but a copy in `~/bin` is killed, verify and reapply its ad-hoc signature:

```sh
codesign --verify --verbose=2 ~/bin/hpnssh
codesign --force --sign - ~/bin/hpnssh
codesign --verify --verbose=2 ~/bin/hpnssh
```

Copy after stripping, then sign the final copy. Also confirm that its AWS-LC
dependency still resolves:

```sh
otool -L ~/bin/hpnssh
```

## AWS-LC Cannot Be Loaded

A missing `libcrypto.dylib` path or an AWS-LC upgrade can leave a copied or old
binary unusable. For the Homebrew package, rebuild both sides of the linkage:

```sh
brew reinstall aws-lc
brew reinstall hpnssh-awslc
brew test hpnssh-awslc
```

Do not replace an AWS-LC dylib with an OpenSSL or LibreSSL dylib. They are not
ABI-compatible substitutes.

## Missing Global Known-Hosts Files

The bottle creates empty global stores at:

```text
/opt/homebrew/etc/hpnssh/ssh_known_hosts
/opt/homebrew/etc/hpnssh/ssh_known_hosts2
```

If either is missing from a Homebrew installation, reinstall the formula. A
direct source installation can create empty `0644` files under its own
`etc/hpnssh` directory. These are optional global stores; per-user host keys
remain in `~/.ssh/known_hosts`.

## Check Linked Libraries

```sh
otool -L "$(command -v hpnssh)"
otool -L "$(command -v hpnsftp)"
```

The supported build should show AWS-LC `libcrypto`, macOS zlib, and Apple's
Kerberos framework. `hpnsftp` should also show macOS libedit. It should not
show `libbsm`, Homebrew zlib-ng-compat, Homebrew libedit, or OpenSSL 3.

## Use With sshfs

For `macos-fuse-t/sshfs`, select the Homebrew HPN client explicitly:

```sh
sshfs user@host:/remote /mount/point \
  -o ssh_command='/opt/homebrew/bin/hpnssh -o Fallback=no'
```

For a direct installation, replace the path with
`/opt/hpnssh-awslc-system-zlib/bin/hpnssh`.

## Fallback Repeats Port 22

This project sets both HPN and standard SSH defaults to port `22`. Disable the
HPN fallback attempt when it would retry the same endpoint:

```sh
hpnssh -o Fallback=no host
```

## Regression Test Stops At Recursive SCP

On the validated macOS 26 environment, the full upstream suite can report
`Directory loop detected` when `/usr/bin/diff -r` follows the test fixture's
absolute symlink. Preserve the log and run focused transfer and formula tests;
do not classify unrelated transfer failures as this known test-harness issue.

## hpnsshd Conflicts With Remote Login

Both use port `22` by default. Do not start `hpnsshd` beside macOS Remote Login
without selecting a nonconflicting listener and obtaining any required
administrator or organization approval. The bottle does not install host
keys or start the server automatically.

## References

- [macos-fuse-t sshfs](https://github.com/macos-fuse-t/sshfs)
- Apple manuals: `man codesign`, `man otool`, and `man ssh_config`
