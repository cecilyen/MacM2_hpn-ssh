# Packaging

The supported binary distribution is the bottle in the separate
[cecilyen/homebrew-hpnssh](https://github.com/cecilyen/homebrew-hpnssh) tap.
This repository contains source-build, validation, benchmark, cleanup, and
direct-archive tooling.

## Homebrew Publication

The tap maintains its own formulae, bottles, and release notes. Check the
[tap releases](https://github.com/cecilyen/homebrew-hpnssh/releases) for current
versions. Source-build and direct-archive updates in this repository do not
change the tap.

## Recorded 18.11.1 Bottle

| Field | Value |
| --- | --- |
| Formula | `cecilyen/hpnssh/hpnssh-awslc` |
| Release tag | `hpnssh-awslc-18.11.1-macos26-arm64` |
| Bottle tag | `arm64_tahoe` |
| Runtime Homebrew dependency | `aws-lc` |
| Bottle file | `hpnssh-awslc-18.11.1.arm64_tahoe.bottle.tar.gz` |
| SHA-256 | `46f63781d3eb61fae765b4eef2c36132aa116995fe1e3ba54511c98c3c03ce83` |

Release page:
[HPN-SSH 18.11.1 AWS-LC bottle](https://github.com/cecilyen/homebrew-hpnssh/releases/tag/hpnssh-awslc-18.11.1-macos26-arm64)

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

1. Built with `brew install --build-bottle` and packaged as rebuild `0`.
2. Checked with `brew style`, `brew audit --strict`, and `brew test`.
3. Downloaded from the public GitHub release into a shorter, second Homebrew
   prefix to exercise padded-prefix relocation.
4. Checked for ARM64 Mach-O binaries, ad-hoc signatures, port `22`, runtime
   linkage, and absence of build-prefix strings and host private keys.
5. Passed `brew test` after the cross-prefix pour.

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
release/hpnssh-18.12.1-macos26-arm64/
```

Pass `--all-variants` only when all local comparison builds are intentional:

```sh
scripts/package-github-release.sh --all-variants
```

Package both current AWS-LC and OpenSSL profiles, requiring both to pass:

```sh
scripts/package-github-release.sh --current-variants --require-all
```

The required HPN-SSH version is derived from `--release-tag`, so older
source builds cannot be mislabeled as the current release. Archives preserve
the configured helper paths and are intended for manual testing. Use the
matching source build's installation target when deploying a server.

The packager validates version, ARM64 architecture, signatures, preferred
system-libedit linkage, and absence of `libbsm`. Do not publish an archive
that contains host keys, local configuration, logs, or an unvalidated build.

## References

- [Homebrew bottles](https://docs.brew.sh/Bottles)
- [Creating a Homebrew tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)
- [GitHub CLI release upload](https://cli.github.com/manual/gh_release_upload)
