# Project Layout

Source and publication files stay in Git. Build trees, logs, profiles, and
release output are generated and ignored.

## Root Repository

```text
README.md
docs/
scripts/
projects/
benchmarks/crypto/
```

Generated root paths:

```text
build/
build-awslc/
build-awslc-system-zlib/
build-awslc-zlibng/
logs/
profiles/
release/
dist/
```

## Homebrew Tap

`homebrew-tap/` is an ignored local checkout of the separate public
[cecilyen/homebrew-hpnssh](https://github.com/cecilyen/homebrew-hpnssh)
repository. It contains:

```text
Formula/hpnssh-awslc.rb
README.md
RELEASE.md
scripts/build-bottle.sh
scripts/upload-release.sh
```

The tap repository stores the recipe and release tooling. Bottle tarballs and
JSON are generated under its ignored `dist/` directory and uploaded as
GitHub Release assets.

## Cleanup

Dry run:

```sh
scripts/clean-generated-artifacts.sh
```

Keep the newest two runs per variant:

```sh
scripts/clean-generated-artifacts.sh --apply --keep-latest 2
```

Remove all known generated build, log, profile, and root release directories:

```sh
scripts/clean-generated-artifacts.sh --apply --all
```

The cleanup helper operates only on known paths inside this workspace. It does
not touch `/opt/hpnssh*`, `/opt/homebrew`, or the separate tap's published
GitHub assets.
