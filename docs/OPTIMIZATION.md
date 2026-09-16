# Optimization

The publication profile favors a broadly compatible Apple Silicon binary over
M2-specific tuning. Network, storage, latency, and the remote SSH endpoint
usually dominate end-to-end performance after the basic crypto path is fast
enough.

## Publication Profile

```sh
CFLAGS="-O3 -arch arm64 -flto=thin -pipe"
CXXFLAGS="-O3 -arch arm64 -flto=thin -pipe"
LDFLAGS="-arch arm64 -flto=thin -Wl,-dead_strip"
```

This profile is the default in
`scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh`.

- `-O3` enables aggressive scalar and loop optimization.
- `-arch arm64` produces Apple Silicon code without selecting one M-series
  microarchitecture.
- ThinLTO provides cross-module optimization with lower build cost than full
  LTO.
- `-pipe` changes compiler temporary-file handling; it does not make the
  resulting SSH binary faster.
- `-Wl,-dead_strip` removes unreachable Mach-O code and data.

`-g0` is optional. Release binaries are stripped with `strip -S`, then ad-hoc
signed, so adding `-g0` is not required to remove final debug sections.

## Local CPU Tuning

For a binary that will run only on an M2-class machine:

```sh
HPNSSH_BASE_OPT_FLAGS="-O3 -arch arm64 -mcpu=apple-m2 -flto=thin -pipe" \
HPNSSH_BASE_LDFLAGS="-arch arm64 -flto=thin -Wl,-dead_strip" \
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh --tag hpn-18.11.0
```

Do not publish this as a general M1-and-newer bottle. Measure it against the
generic build with representative transfers before keeping it.

## Profile-Guided Optimization

Use the same LLVM toolchain for compilation and profile merging.

Build an instrumented binary:

```sh
PGO_RAW="$PWD/profiles/hpnssh-pgo-raw"
mkdir -p "$PGO_RAW"

HPNSSH_BASE_OPT_FLAGS="-O3 -arch arm64 -flto=thin -pipe -fprofile-generate=${PGO_RAW}" \
HPNSSH_BASE_LDFLAGS="-arch arm64 -flto=thin -Wl,-dead_strip -fprofile-generate=${PGO_RAW}" \
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh --tag hpn-18.11.0
```

Train the generated `hpnssh` and `hpnscp` with representative hosts, file
sizes, directions, ciphers, and KEX algorithms:

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
/opt/homebrew/opt/llvm/bin/llvm-profdata merge -output "$PROF" \
  "${PGO_RAW}"/*.profraw

HPNSSH_BASE_OPT_FLAGS="-O3 -arch arm64 -flto=thin -pipe -fprofile-use=${PROF}" \
HPNSSH_BASE_LDFLAGS="-arch arm64 -flto=thin -Wl,-dead_strip -fprofile-use=${PROF}" \
scripts/build-hpnssh-macos-arm64-awslc-system-zlib.sh --tag hpn-18.11.0
```

PGO affects HPN-SSH/OpenSSH objects, not the prebuilt AWS-LC or macOS system
libraries. A narrow training set can regress untrained workloads, so compare
latency, throughput, CPU, and memory before publication.

## Flags To Avoid

- Do not use `-ffast-math`. SSH is not a floating-point workload, so the flag
  provides no useful crypto or transport optimization and weakens floating
  point semantics globally.
- Do not force `-fstrict-aliasing`. OpenSSH configure intentionally adds
  `-fno-strict-aliasing`; overriding it can expose undefined behavior.
- Do not assume full LTO is faster than ThinLTO at runtime. Benchmark both if
  build-time and memory costs are acceptable.

## Strip Order

`-Wl,-dead_strip` and `strip -S` perform different jobs. Keep this order:

1. Link with `-Wl,-dead_strip`.
2. Strip debug symbols with `strip -S`.
3. Apply the final ad-hoc code signature.

## References

- [Clang command guide](https://clang.llvm.org/docs/CommandGuide/clang.html)
- [Clang profile-guided optimization](https://clang.llvm.org/docs/UsersManual.html#profile-guided-optimization)
- [LLVM llvm-profdata](https://llvm.org/docs/CommandGuide/llvm-profdata.html)
- [Clang strict aliasing](https://clang.llvm.org/docs/UsersManual.html#strict-aliasing)
