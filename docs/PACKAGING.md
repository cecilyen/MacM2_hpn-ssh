# Packaging

Publish source from the root repository and publish validated binary tarballs
from `release/` as GitHub Release assets.

The preferred publishable binary variant is `hpnssh-awslc-system-zlib`, which
uses Homebrew AWS-LC for `libcrypto` and macOS `/usr/lib/libz.1.dylib` for
compression. Its `hpnsftp` binary links macOS `/usr/lib/libedit.3.dylib`, so
the minimal Homebrew runtime set is only `aws-lc`. The supported runtime target
is documented in `docs/SYSTEM_REQUIREMENTS.md`.

## GitHub Binary Release Assets

Generate the preferred release-ready binary archive from the latest local build
output:

```sh
scripts/package-github-release.sh
```

To package every known local variant instead of only the preferred AWS-LC +
macOS zlib build:

```sh
scripts/package-github-release.sh --all-variants
```

The output directory is:

```text
release/hpnssh-18.9.0-macos26-arm64/
```

The packager validates selected variants before archiving them. It skips
binaries that fail `hpnssh -V`, are not `arm64`, or still link `libbsm`. Each
release directory includes:

- `*.tar.gz` binary archives.
- `SHA256SUMS`.
- `MANIFEST.txt`.
- `SKIPPED.txt`.
- `RELEASE_NOTES.md`.

## Upload Release Assets

```sh
gh release upload hpnssh-18.9.0-macos26-arm64 \
  release/hpnssh-18.9.0-macos26-arm64/*.tar.gz \
  release/hpnssh-18.9.0-macos26-arm64/SHA256SUMS \
  release/hpnssh-18.9.0-macos26-arm64/MANIFEST.txt \
  release/hpnssh-18.9.0-macos26-arm64/SKIPPED.txt \
  release/hpnssh-18.9.0-macos26-arm64/RELEASE_NOTES.md
```

Add `--clobber` when replacing an existing asset with a regenerated file.

## References

- GitHub CLI release upload: <https://cli.github.com/manual/gh_release_upload>
