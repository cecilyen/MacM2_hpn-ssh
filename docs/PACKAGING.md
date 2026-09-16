# Packaging

The supported binary distribution is the bottle in the separate
[cecilyen/homebrew-hpnssh](https://github.com/cecilyen/homebrew-hpnssh) tap.
This repository contains source-build, validation, benchmark, cleanup, and
direct-archive tooling.

## Published Bottle

| Field | Value |
| --- | --- |
| Formula | `cecilyen/hpnssh/hpnssh-awslc` |
| Release tag | `hpnssh-awslc-18.11.0-macos26-arm64` |
| Bottle tag | `arm64_tahoe` |
| Runtime Homebrew dependency | `aws-lc` |
| Bottle file | `hpnssh-awslc-18.11.0.arm64_tahoe.bottle.tar.gz` |
| SHA-256 | `798f6a4b6964486e88a96ebccc182840720f766c5af37e7e5d54e6a0ddddc62c` |

Release page:
[HPN-SSH 18.11.0 AWS-LC bottle](https://github.com/cecilyen/homebrew-hpnssh/releases/tag/hpnssh-awslc-18.11.0-macos26-arm64)

Install it through Homebrew so dependency handling, relocation, and checksum
verification are automatic:

```sh
brew tap cecilyen/hpnssh
brew install hpnssh-awslc
```

The release also contains the bottle JSON, formula snapshot, checksum list,
and release documentation. It does not contain source worktrees, build logs,
local SSH configuration, or host private keys.

## Bottle Validation

Before publication, the bottle was:

1. Built with `brew install --build-bottle`.
2. Checked with `brew audit --strict` and `brew test`.
3. Poured into a second Homebrew prefix to exercise relocation.
4. Checked for ARM64 Mach-O binaries, ad-hoc signatures, port `22`, runtime
   linkage, and absence of build-prefix strings and host private keys.
5. Downloaded from the public GitHub release and tested again.

The tap repository is the canonical location for its formula and bottle
release process. The ignored `homebrew-tap/` directory in this workspace is
only a local checkout.

## Direct Archives

Direct archives are secondary artifacts for manual installation testing. The
packager needs Homebrew `bfs` and `uutils-coreutils` in addition to a completed
build:

```sh
brew install bfs uutils-coreutils
scripts/package-github-release.sh
```

Default output:

```text
release/hpnssh-18.11.0-macos26-arm64/
```

Pass `--all-variants` only when all local comparison builds are intentional:

```sh
scripts/package-github-release.sh --all-variants
```

The packager validates version, ARM64 architecture, signatures, preferred
system-libedit linkage, and absence of `libbsm`. Do not publish an archive
that contains host keys, local configuration, logs, or an unvalidated build.

## References

- [Homebrew bottles](https://docs.brew.sh/Bottles)
- [Creating a Homebrew tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)
- [GitHub CLI release upload](https://cli.github.com/manual/gh_release_upload)
