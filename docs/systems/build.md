# Build System

Silt is an OCaml binary that statically links a Rust library. The build has two phases: Rust first, then OCaml.

## Build order

```
1. cargo build --release          (in rust/silt_embed/)
   → produces libsilt_embed.a    (~153MB, includes model weights)

2. dune build                     (at repo root)
   → links libsilt_embed.a into the OCaml binary
   → produces _build/default/bin/main.exe
```

The OCaml build depends on the Rust static library existing. If you change Rust code, you must rebuild Rust first.

## Dune configuration

### FFI library (`ffi/dune`)

The FFI library compiles C stubs and links the Rust archive:

- `foreign_stubs`: compiles `silt_embed_stubs.c` and `musl_compat.c`
- `c_library_flags`: generated at build time by a shell rule that resolves the absolute path to `libsilt_embed.a`
- The path resolution uses `SILT_RUST_TARGET` env var for cross-target builds (e.g., musl)

### Executable (`bin/dune`)

The binary links against the `silt` library and `cmdliner`. For static builds, a generated `link_flags.sexp` adds `-ccopt -static` and the musl compatibility object.

### Skill embedding (`lib/dune`)

The skill file (`skill/silt.md`) is embedded into the binary at build time via a dune rule that generates `skill_content.ml` using OCaml's quoted string syntax (`{silt_skill|...|silt_skill}`).

### Version injection (`bin/dune`)

The binary version comes from the `SILT_VERSION` env var, defaulting to `dev`. A dune rule generates `version.ml` containing `let v = "<version>"`.

## Static linking (Linux)

For fully static Linux binaries, we use:

- **Rust**: `--target x86_64-unknown-linux-musl`
- **OCaml**: `opam switch` with `ocaml-option-musl` and `ocaml-option-static`

### The _dl_find_object problem

GCC 14's `libgcc_eh.a` references `_dl_find_object`, a glibc-only symbol. When linking against musl, this symbol doesn't exist. The fix is `ffi/musl_compat.c`, which provides a weak definition that returns -1 (causing libgcc to fall back to the slower but correct `dl_iterate_phdr` path).

The `.o` file must be linked directly at the executable level (via `link_flags.sexp`), not just compiled into the FFI library archive, because the linker processes archives left-to-right and won't pull our definition in time to resolve the reference from `libgcc_eh.a`.

## CI / Release

GitHub Actions builds three targets:

| Target | Runner | Static |
|--------|--------|--------|
| linux-x86_64 | ubuntu-latest | Yes (musl) |
| linux-aarch64 | ubuntu-24.04-arm | Yes (musl) |
| macos-aarch64 | macos-latest | No (macOS doesn't support static) |

Release versions are `vN` (monotonically increasing, from `github.run_number`). The `SILT_VERSION` env var is set during the release build.

## Justfile

Common build recipes:

```sh
just build          # build Rust + OCaml (dynamic)
just build-static   # fully static Linux binary
just test           # run all tests
just run -- search "query"
just setup          # first-time: install deps, download model, build
```

## Troubleshooting

If dune cannot find libsilt_embed.a, ensure you have built the Rust crate first with `cargo build --release`. The path resolution in ffi/dune uses a shell rule that may cache stale paths — run `dune clean` to reset.
