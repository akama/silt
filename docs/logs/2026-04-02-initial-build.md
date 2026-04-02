# 2026-04-02: Initial build of silt v0.1

## What was done

Built the complete silt CLI from the design doc. The tool provides git-native
semantic memory for LLM coding agents.

### Components built

1. **Rust static library** (`rust/silt_embed/`) — Wraps the all-MiniLM-L6-v2
   sentence transformer model using candle (pure Rust inference). Exposes C ABI
   with `silt_embed()` and `silt_embed_dims()`. Model weights (~87MB safetensors)
   are embedded via `include_bytes!` at compile time.

2. **OCaml FFI bridge** (`ffi/`) — C stubs calling into the Rust static library,
   with OCaml externals providing `Silt_ffi.Embed.embed : string -> float array`.

3. **Core library** (`lib/`) — Memory parsing with optional YAML frontmatter,
   file-based store (one file per key in `.silt/memories/`), and search engine
   with brute-force cosine similarity over cached embedding index.

4. **CLI** (`bin/`) — cmdliner-based with subcommands: init, store, get, search,
   forget, list, rebuild. Includes `--json` output for agent integration.

### Test results

- Rust unit tests: 2/2 pass (embedding correctness + similarity ranking)
- OCaml unit tests: 6/6 pass (memory parsing, serialization, roundtrip, store ops)
- End-to-end: init, store, get, list, search, forget, rebuild all verified

### Binary

- Size: ~119MB (includes embedded model weights)
- Platform: linux-x86_64
- Single binary, zero runtime dependencies

### Notes

- Search ranking for very short memories isn't always ideal — the model works
  better with longer, more descriptive text
- The ffi/dune build uses a shell rule to resolve the absolute path to the Rust
  static library at build time
