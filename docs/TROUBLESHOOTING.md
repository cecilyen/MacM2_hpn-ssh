# Troubleshooting

Main conclusion: most local failures come from dynamic library paths, macOS code
signing after copying binaries, or missing optional global configuration files.

## Copied Binary Is Killed By macOS

If `hpnssh` works inside the build tree but fails after copying to `~/bin`, sign
the copied binary:

```sh
codesign --force --sign - ~/bin/hpnssh
```

The build script signs binaries after stripping. Copying or modifying a Mach-O
binary can require signing the final file again.

## Missing Global Known Hosts Files

Verbose client output may show:

```text
load_hostkeys: fopen /opt/hpnssh-awslc/etc/hpnssh/ssh_known_hosts: No such file or directory
load_hostkeys: fopen /opt/hpnssh-awslc/etc/hpnssh/ssh_known_hosts2: No such file or directory
```

Those are optional global host-key stores. User host keys still live in
`~/.ssh/known_hosts`. To silence the message:

```sh
sudo mkdir -p /opt/hpnssh-awslc/etc/hpnssh
sudo touch /opt/hpnssh-awslc/etc/hpnssh/ssh_known_hosts /opt/hpnssh-awslc/etc/hpnssh/ssh_known_hosts2
sudo chmod 0644 /opt/hpnssh-awslc/etc/hpnssh/ssh_known_hosts /opt/hpnssh-awslc/etc/hpnssh/ssh_known_hosts2
```

## Check Linked Libraries

```sh
otool -L /path/to/hpnssh
```

Expected AWS-LC + zlib-ng linkage includes Homebrew `aws-lc` for `libcrypto`,
Homebrew `zlib-ng-compat` for `libz`, and Apple's Kerberos framework. It should
not include `libbsm`.

## Use With sshfs

For macos-fuse-t `sshfs`, pass the HPN-SSH client path through `ssh_command`:

```sh
sshfs user@host:/remote /mount/point \
  -o ssh_command=/opt/hpnssh-awslc-zlibng/bin/hpnssh
```

When you need to disable HPN's fallback behavior explicitly:

```sh
sshfs user@host:/remote /mount/point \
  -o ssh_command='/opt/hpnssh-awslc-zlibng/bin/hpnssh -o Fallback=no'
```

## Fallback Port Loop

This project patches HPN's default client port from `2222` to `22`. If a client
prints a fallback message that also targets port `22`, run with:

```sh
hpnssh -o Fallback=no host
```

## References

- macos-fuse-t sshfs: <https://github.com/macos-fuse-t/sshfs>
- Apple `codesign` manual: `man codesign`
- Apple `otool` manual: `man otool`
