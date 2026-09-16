# Project Layout And Cleanup

Only source, scripts, and documentation belong in Git. Build trees, logs,
profiles, benchmark output, bottles, and direct archives are generated and
ignored.

## Tracked Files

```text
README.md                 Project entry point
docs/                     Build, runtime, optimization, and release guidance
scripts/                  Build, benchmark, package, and cleanup tools
projects/README.md        Supported and legacy build-profile matrix
benchmarks/crypto/        Reproducible libcrypto microbenchmark source
```

## Generated Paths

```text
build*/                   Source worktrees and compiled binaries
logs/                     Timestamped build logs
profiles/                 PGO data
release/                  Direct-install archives
dist/                     Packaging output
benchmarks/results/       SSH benchmark results
benchmarks/crypto/build/  Crypto benchmark executable
benchmarks/crypto/results/ Crypto benchmark CSV output
```

`homebrew-tap/` is an ignored checkout of the separate public
[Homebrew tap](https://github.com/cecilyen/homebrew-hpnssh). Its own Git
history, formula, scripts, and `dist/` output do not belong to this
repository.

## Cleanup

Preview removal while keeping the newest two runs per build profile:

```sh
scripts/clean-generated-artifacts.sh
```

Keep only the newest run and matching number of logs:

```sh
scripts/clean-generated-artifacts.sh --apply --keep-latest 1 --logs
```

Remove all known generated build trees, logs, profiles, and root release
directories:

```sh
scripts/clean-generated-artifacts.sh --apply --all
```

`--all` also removes the newest validated local build. Review the default dry
run before using it.

The cleanup helper accepts only known workspace paths. It does not touch
`/opt/hpnssh*`, `/opt/homebrew`, user SSH files, or published GitHub assets.
