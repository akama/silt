# Silt — Git-native memory for LLM coding agents

set dotenv-load := false

rust_dir := "rust/silt_embed"

# List available recipes
default:
    @just --list

# Download model weights (~87MB)
download-model:
    {{rust_dir}}/download_model.sh

# Build the Rust static library
build-rust target="":
    cd {{rust_dir}} && source ~/.cargo/env && cargo build --release {{ if target != "" { "--target " + target } else { "" } }}

# Build the OCaml binary (requires Rust lib)
build-ocaml:
    eval $(opam env --switch=silt) && dune build

# Build everything (dynamic, glibc)
build: build-rust build-ocaml

# Build fully static Linux binary (musl)
build-static:
    cd {{rust_dir}} && source ~/.cargo/env && cargo build --release --target x86_64-unknown-linux-musl
    eval $(opam env --switch=silt-static) && SILT_RUST_TARGET=x86_64-unknown-linux-musl dune build
    @ldd _build/default/bin/main.exe 2>&1 | grep -q "not a dynamic executable" && echo "Static binary built successfully" || echo "WARNING: binary is not fully static"

# Run Rust tests
test-rust:
    cd {{rust_dir}} && source ~/.cargo/env && cargo test --release

# Run OCaml tests
test-ocaml:
    eval $(opam env --switch=silt) && dune runtest

# Run all tests
test: test-rust test-ocaml

# Clean build artifacts
clean:
    cd {{rust_dir}} && source ~/.cargo/env && cargo clean
    eval $(opam env --switch=silt) && dune clean

# Full clean build from scratch
rebuild: clean download-model build test

# Run silt (pass args after --)
run *ARGS:
    eval $(opam env --switch=silt) && dune exec -- silt {{ARGS}}

# Show binary size and linking info
size:
    @ls -lh _build/default/bin/main.exe 2>/dev/null || echo "Not built yet. Run: just build"
    @ldd _build/default/bin/main.exe 2>&1 || true

# Install OCaml dependencies via opam
setup-ocaml:
    opam switch create silt 5.3.0 --yes || true
    eval $(opam env --switch=silt) && opam install dune cmdliner yaml fmt logs --yes

# Set up the static musl OCaml switch
setup-static:
    opam switch create silt-static ocaml-variants.5.3.0+options ocaml-option-musl ocaml-option-static --yes || true
    eval $(opam env --switch=silt-static) && opam install dune cmdliner yaml fmt logs --yes

# Full first-time setup
setup: setup-ocaml download-model build test
    @echo "Setup complete. Run 'just run --help' to get started."
