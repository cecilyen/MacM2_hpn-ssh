# Packaging

Main conclusion: publish source from the root repository and publish validated
binary tarballs from `release/` as GitHub Release assets. Homebrew formulae are
intentionally not included yet.

## GitHub Binary Release Assets

Generate release-ready binary archives from the latest local build outputs:

```sh
scripts/package-github-release.sh
```

The output directory is:

```text
release/hpnssh-18.9.0-macos26-arm64/
```

The packager validates each variant before archiving it. It skips binaries that
fail `hpnssh -V`, are not `arm64`, or still link `libbsm`. Each release
directory includes:

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

## References

- GitHub CLI release upload: <https://cli.github.com/manual/gh_release_upload>
