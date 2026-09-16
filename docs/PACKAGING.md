# Packaging

The preferred binary distribution is the Homebrew bottle in the separate
[cecilyen/homebrew-hpnssh](https://github.com/cecilyen/homebrew-hpnssh) tap.
The root repository remains the source-build and benchmark project.

## Homebrew Bottle

Current release:

- Tag: `hpnssh-awslc-18.11.0-macos26-arm64`
- Bottle tag: `arm64_tahoe`
- Runtime Homebrew dependency: `aws-lc`
- Release: [HPN-SSH 18.11.0 AWS-LC bottle](https://github.com/cecilyen/homebrew-hpnssh/releases/tag/hpnssh-awslc-18.11.0-macos26-arm64)

Install:

```sh
brew tap cecilyen/hpnssh
brew install hpnssh-awslc
```

The bottle recipe, build script, upload script, release procedure, and
checksums live in the tap repository. The bottle is built with
`brew install --build-bottle`, tested with `brew test`, and validated by
pouring it into a second Homebrew prefix to exercise binary relocation.

The release assets are:

- `hpnssh-awslc-18.11.0.arm64_tahoe.bottle.tar.gz`
- `hpnssh-awslc--18.11.0.arm64_tahoe.bottle.json`
- `hpnssh-awslc.rb`
- `SHA256SUMS`
- Release and tap documentation

Host private keys, local SSH configuration, source trees, and build logs are
not release assets.

## Direct Archives

The root repository can still create direct-install archives from local build
outputs:

```sh
scripts/package-github-release.sh
```

To include every available local variant:

```sh
scripts/package-github-release.sh --all-variants
```

Default output:

```text
release/hpnssh-18.11.0-macos26-arm64/
```

The direct-archive packager validates the version, ARM64 architecture,
signatures, system libedit for the preferred variant, and absence of
`libbsm`. Direct archives are secondary to the tested Homebrew bottle.

## References

- [Homebrew bottles](https://docs.brew.sh/Bottles)
- [Creating a Homebrew tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)
- [GitHub CLI release upload](https://cli.github.com/manual/gh_release_upload)
