# Optimization

The published Apple Silicon build uses generic arm64 ThinLTO flags:
`-O3 -arch arm64 -flto=thin -pipe` and
`-arch arm64 -flto=thin -Wl,-dead_strip`. Profile-Guided Optimization (PGO) is
optional. Do not use `-ffast-math` or force `-fstrict-aliasing` for this code.

## Recommended Publication Profile

```sh
CFLAGS="-O3 -arch arm64 -flto=thin -pipe"
CXXFLAGS="-O3 -arch arm64 -flto=thin -pipe"
LDFLAGS="-arch arm64 -flto=thin -Wl,-dead_strip"
```

This is the default profile used by
`scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh`. It avoids
M2-specific `-mcpu` tuning so the binary remains a more general M1-and-newer
Apple Silicon build.

## Optional Local M2 Max Profile

```sh
CFLAGS="-O3 -flto -g0 -mcpu=apple-m2"
CXXFLAGS="-O3 -flto -g0 -mcpu=apple-m2"
LDFLAGS="-flto -Wl,-dead_strip"
```

The shared base builder can still supply local full-LTO flags and detect an
Apple CPU target. Use that path only when you are running a controlled local
benchmark rather than preparing a general release artifact.

## General Apple Silicon Build

For a portable Apple Silicon build intended for M1 and later systems:

```sh
CFLAGS="-O3 -flto=thin -g0"
CXXFLAGS="-O3 -flto=thin -g0"
LDFLAGS="-flto=thin -Wl,-dead_strip"
```

Thin Link-Time Optimization (ThinLTO) is usually a better packaging default
than full LTO because it scales better during build while preserving many
cross-module optimization benefits.

## Profile-Guided Optimization

Build an instrumented binary:

```sh
PGO_RAW="$PWD/profiles/hpnssh-pgo-raw"
mkdir -p "$PGO_RAW"

CFLAGS="-fprofile-generate=${PGO_RAW}" \
CXXFLAGS="-fprofile-generate=${PGO_RAW}" \
LDFLAGS="-fprofile-generate=${PGO_RAW}" \
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh --tag hpn-18.9.0
```

Train it with real workloads:

```sh
PGO_BIN="$PWD/build-awslc-system-zlib/runs/<run>/hpn-ssh"

LLVM_PROFILE_FILE="${PGO_RAW}/hpnssh-%p.profraw" \
  "${PGO_BIN}/hpnssh" -o Fallback=no your-host true

LLVM_PROFILE_FILE="${PGO_RAW}/hpnscp-%p.profraw" \
  "${PGO_BIN}/hpnscp" -o Fallback=no ./largefile your-host:/tmp/
```

Merge and rebuild:

```sh
PROF="$PWD/profiles/hpnssh.profdata"

xcrun llvm-profdata merge -output "$PROF" "$PGO_RAW"

CFLAGS="-fprofile-use=${PROF}" \
CXXFLAGS="-fprofile-use=${PROF}" \
LDFLAGS="-fprofile-use=${PROF} -Wl,-dead_strip" \
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh --tag hpn-18.9.0
```

Limitations: PGO optimizes HPN-SSH/OpenSSH objects only. It does not optimize
Homebrew AWS-LC or macOS system zlib unless those libraries are rebuilt with
their own PGO profiles.

## Flags To Avoid

- Do not use `-ffast-math`. HPN-SSH is not a floating-point workload, and Clang
  documents that this flag enables assumptions such as no NaNs, no infinities,
  reassociation, reciprocal transforms, and no signed-zero distinction.
- Do not force `-fstrict-aliasing`. OpenSSH configure intentionally adds
  `-fno-strict-aliasing`, and strict-aliasing violations are undefined behavior.

## Strip And Dead Strip

`-Wl,-dead_strip` is a linker reachability optimization for Mach-O functions and
data. It does not replace `strip -S`, which removes debug symbol entries. Keep
the release order as:

1. Link with `-Wl,-dead_strip`.
2. Strip debug symbols.
3. Apply the ad-hoc code signature.

## References

- Clang optimization levels: <https://clang.llvm.org/docs/CommandGuide/clang.html#cmdoption-o0>
- Clang Profile-Guided Optimization: <https://clang.llvm.org/docs/UsersManual.html#profile-guided-optimization>
- LLVM `llvm-profdata`: <https://llvm.org/docs/CommandGuide/llvm-profdata.html>
- Clang `-ffast-math`: <https://clang.llvm.org/docs/UsersManual.html#cmdoption-ffast-math>
- Clang strict aliasing: <https://clang.llvm.org/docs/UsersManual.html#strict-aliasing>
