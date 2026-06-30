# Project Layout

Main conclusion: source and packaging files are small and stable; build trees,
logs, profiles, and release output are generated artifacts and should stay out
of Git.

## Source Files

```text
README.md
docs/
docs/SYSTEM_REQUIREMENTS.md
scripts/
projects/
```

## Generated Files

```text
build/
build-awslc/
build-awslc-system-zlib/
build-awslc-zlibng/
logs/
profiles/
release/
```

The generated directories are ignored by the root `.gitignore`.

## GitHub Publication

Use the root repository for source code and docs. Use generated tarballs under
`release/<tag>/` as GitHub Release assets. Do not commit the generated release
archives into the source tree.

## Cleanup Helper

Dry-run cleanup:

```sh
scripts/clean-generated-artifacts.sh
```

Apply cleanup while keeping the newest two build runs per variant:

```sh
scripts/clean-generated-artifacts.sh --apply --keep-latest 2
```

Remove all generated build, log, profile, and release directories:

```sh
scripts/clean-generated-artifacts.sh --apply --all
```

Limitations: the cleanup helper only acts on known generated paths under this
workspace. It does not touch installation prefixes such as `/opt/hpnssh`.
