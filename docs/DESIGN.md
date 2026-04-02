# Silt — Git-native memory for LLM coding agents

## Overview

Silt is a CLI tool that gives LLM coding agents persistent, searchable, branch-aware memory. Memories are plain text files stored in a configurable hidden directory within a git repository. Semantic search is powered by a local embedding model compiled as a Rust static library and linked directly into the OCaml binary via C FFI. The result is a single statically-linked binary per platform with no runtime dependencies.

## Design principles

- **Plain text as source of truth.** Memories are human-readable files in git. Everything else is derived.
- **Embeddings are ephemeral.** Never stored in git. Rebuilt locally on demand from a model baked into the binary.
- **Single binary, zero dependencies.** The Rust embedding engine is statically linked. No Python, no shared libraries, no model downloads.
- **Git-native branching.** Memory visibility follows git's DAG. Branch from main, add memories, and they're invisible from main until you merge.
- **Conflict-resistant by design.** One file per memory key. Git auto-merges non-conflicting tree entries. The embedding index is derived, never committed.

## Architecture

```
┌──────────────────────────────────────────┐
│              silt (OCaml)              │
│                                          │
│  CLI ─── Memory store ─── Search engine  │2
│                │                │        │
│           File I/O         FFI calls     │
│           (plain text)         │        │
│                          ┌─────┴──────┐  │
│                          │ libsilt  │  │
│                          │  (Rust .a) │  │
│                          │            │  │
│                          │ candle +   │  │
│                          │ tokenizer +│  │
│                          │ model wts  │  │
│                          └────────────┘  │
└──────────────────────────────────────────┘
```

### Rust static library (`libsilt_embed`)

A `staticlib` crate exposing a C ABI. Model weights (quantized all-MiniLM-L6-v2, ~30MB) are embedded via `include_bytes!`. Inference uses the `candle` framework — pure Rust, no ONNX Runtime dependency.

```rust
#[no_mangle]
pub extern "C" fn silt_embed(
    input: *const c_char,
    input_len: usize,
    output: *mut f32,     // caller-allocated, 384 floats
) -> i32;

#[no_mangle]
pub extern "C" fn silt_embed_dims() -> usize; // returns 384
```

### OCaml FFI bridge

Thin C stub + OCaml externals. No subprocess, no extraction, no temp files.

```ocaml
module Embed : sig
  val dims : int
  val embed : string -> float array
  val embed_batch : string list -> float array list
end
```

### Build pipeline

```
cargo build --release --target <triple>   → libsilt_embed.a
dune build --profile=static               → silt (single binary)
```

Per-platform CI matrix (linux-x86_64, linux-aarch64, macos-x86_64, macos-aarch64). Linux builds use musl for full static linking.

## File layout

```
.silt/                        # configurable, defaults to .silt
  config                        # tool configuration
  memories/
    auth-jwt                    # one file per memory, filename is the key
    db-schema-conventions
    error-handling-patterns
    ci-pipeline-notes
  .cache/                       # gitignored
    index.bin                   # serialized embedding matrix + key map
    model-version               # tracks which model built the index
```

### Memory file format

Plain text with optional YAML frontmatter. The filename is the key.

```
---
tags: [auth, security]
created: 2025-03-15
---
The auth service uses JWT with RS256 signing. Keys are rotated
monthly via Vault. Tokens expire after 1 hour. Refresh tokens
are stored server-side in Redis with a 30-day TTL.
```

Frontmatter is optional. A memory can be as simple as:

```
Use `dune build @fmt` before committing. The project enforces
ocamlformat 0.26.2.
```

### Config file

```yaml
memory_dir: .silt/memories       # where memories live
cache_dir: .silt/.cache          # gitignored index cache
```

### .gitignore entry

The tool appends to `.gitignore` on `silt init` if not present:

```
.silt/.cache/
```

## CLI interface

### `silt init`

Initialize silt in the current repository. Creates `.silt/`, adds cache directory to `.gitignore`.

```
$ silt init
Initialized silt in .silt/
Added .silt/.cache/ to .gitignore
```

### `silt store <key>`

Store a memory. Reads content from stdin or `--message`/`-m` flag.

```
$ silt store auth-jwt -m "Auth uses JWT RS256, keys rotated monthly via Vault"
Stored memory: auth-jwt

$ echo "Run dune build @fmt before committing" | silt store formatting
Stored memory: formatting

$ silt store deployment-notes  # opens $EDITOR
Stored memory: deployment-notes
```

Overwrites if key exists. The change shows up in `git diff` as a normal file modification.

### `silt get <key>`

Retrieve a memory by exact key.

```
$ silt get auth-jwt
The auth service uses JWT with RS256 signing. Keys are rotated
monthly via Vault.
```

### `silt search <query>`

Semantic search across all memories. Builds/updates the embedding index on demand if stale.

```
$ silt search "how does authentication work"
auth-jwt          (0.87)  Auth uses JWT RS256, keys rotated monthly...
session-handling   (0.71)  Sessions are stored in Redis with...
```

Flags:
- `--top-k <n>` — number of results (default: 5)
- `--threshold <f>` — minimum similarity score (default: 0.5)
- `--json` — output as JSON for programmatic consumption

### `silt forget <key>`

Remove a memory. Deletes the file.

```
$ silt forget auth-jwt
Removed memory: auth-jwt
```

### `silt list`

List all memory keys.

```
$ silt list
auth-jwt
db-schema-conventions
error-handling-patterns
formatting
```

Flags:
- `--tags <tag>` — filter by tag from frontmatter
- `--long` — show first line of content alongside key

### `silt rebuild`

Force-rebuild the embedding index. Useful after changing model version or if the cache is corrupted.

```
$ silt rebuild
Embedded 47 memories (384 dims, 12ms)
```

## Search engine

### Index structure

The cache contains a flat float32 matrix and a key-to-row mapping, serialized as a single binary file. On query:

1. Check if index is stale (compare file mtimes in `memories/` against `index.bin` mtime).
2. If stale, re-embed only changed/new memories. Rebuild full index if model version changed.
3. Load index into memory.
4. Embed the query string via `Embed.embed`.
5. Brute-force cosine similarity against all rows.
6. Return top-k results above threshold.

Brute-force is fine at this scale. 1000 memories at 384 dims is a ~1.5MB matrix, scanned in under 1ms. No ANN index needed.

### Incremental updates

The index tracks `(key, mtime, embedding)` tuples. On rebuild:
- New files: embed and append.
- Modified files (mtime changed): re-embed in place.
- Deleted files: remove from index.
- Unchanged files: keep existing embedding.

This keeps the typical `silt search` fast — most invocations skip embedding entirely.

## Merge and conflict handling

### Why conflicts are rare

Each memory is a separate file. Git merges trees entry-by-entry. Two branches adding different memory keys auto-merge with no conflict. The only conflict case is two branches modifying the same key's content, which is uncommon for agent-written memories.

### When conflicts happen

Standard git conflict markers appear in the memory file. The user or agent resolves like any other file. Since memories are plain text, conflicts are easy to read and resolve.

### The index is never a conflict source

The embedding index lives in `.cache/` (gitignored). After any merge, the next `silt search` detects stale index and rebuilds transparently.

## Graceful degradation

The system degrades cleanly at every layer:

- **No embedding model?** Can't happen — it's compiled in.
- **No cache?** Built lazily on first `silt search`.
- **Corrupt cache?** `silt rebuild` or just delete `.cache/`.
- **Want to edit a memory?** Open it in `$EDITOR`. It's a text file.
- **Want to bulk import?** Drop text files in the memories directory.
- **Want to see history?** `git log -p -- .silt/memories/`
- **Want to grep?** `grep -r "pattern" .silt/memories/`

There is no magic state to corrupt. The source of truth is always the plain text files in git.

## Agent integration

Silt is designed to be called by LLM coding agents (Claude Code, Codex, Cursor, etc.) as a shell tool. The `--json` flag on `silt search` enables structured output:

```json
{
  "results": [
    {
      "key": "auth-jwt",
      "score": 0.87,
      "content": "Auth uses JWT RS256...",
      "tags": ["auth", "security"]
    }
  ]
}
```

An agent's `CLAUDE.md` or equivalent can include:

```markdown
Before making changes to a subsystem, run:
  silt search "<description of what you're about to do>"
to check for existing project knowledge.

After learning something important, run:
  silt store <key> -m "<what you learned>"
```

## Scope and non-goals

### v0.1 scope

- `init`, `store`, `get`, `search`, `forget`, `list`, `rebuild`
- Embedded all-MiniLM-L6-v2 (384-dim, quantized)
- Plain text memories with optional YAML frontmatter
- Brute-force cosine similarity search
- JSON output mode
- Static binary builds for linux-x86_64 and macos-aarch64

### Non-goals for v0.1

- **No daemon or server.** Pure CLI, stateless between invocations.
- **No sync protocol.** Memories travel via git push/pull like any other file.
- **No automatic memory creation.** The agent or user explicitly calls `silt store`.
- **No multi-repo memory.** Scoped to one repository. Cross-project memory is a separate repo you manage yourself.
- **No encryption.** Memories are plaintext in git. If the repo is private, the memories are private.

### Future considerations

- **Tag-filtered search.** Combine semantic similarity with frontmatter tag filtering.
- **MCP server mode.** Expose silt as an MCP tool for direct integration with Claude Desktop and Claude Code.
- **Configurable models.** Allow swapping the baked-in model for a different one (requires rebuild from source).
- **jj-native integration.** Use revsets for memory scoping when running under jj.
- **Memory compaction.** LLM-powered summarization to merge related memories.
- **`silt diff <branch>`.** Show what memories exist on one branch but not another.
- **Full-text fallback.** `grep`-based search when the index is unavailable, degrading gracefully.

