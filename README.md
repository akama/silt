# silt

Git-native memory for LLM coding agents. A single static binary with embedded semantic search — no dependencies, no model downloads, no server.

Memories are plain text files in your repo. They travel with `git push`/`pull`, branch with your code, and merge without conflicts. Search is powered by an embedded sentence transformer (all-MiniLM-L6-v2) compiled directly into the binary.

## Install

Download from [releases](https://github.com/akama/silt/releases/latest):

```sh
# Linux x86_64
curl -sL https://github.com/akama/silt/releases/latest/download/silt-linux-x86_64.tar.gz | tar xz
sudo mv silt /usr/local/bin/

# Linux aarch64
curl -sL https://github.com/akama/silt/releases/latest/download/silt-linux-aarch64.tar.gz | tar xz
sudo mv silt /usr/local/bin/

# macOS Apple Silicon
curl -sL https://github.com/akama/silt/releases/latest/download/silt-macos-aarch64.tar.gz | tar xz
sudo mv silt /usr/local/bin/
```

Linux binaries are fully static (musl) and run on any distro.

## Quick start

```sh
silt init                                      # set up .silt/ in your repo
silt store auth -m "JWT RS256, keys via Vault"  # save a memory
silt store db -m "Postgres, UUID primary keys"  # save another
silt search "how does authentication work"      # semantic search
silt get auth                                   # exact key lookup
silt list                                       # list all keys
silt forget auth                                # remove a memory
```

## How it works

```
.silt/
  memories/
    auth          ← plain text, one file per key
    db
  .cache/         ← gitignored, rebuilt on demand
    index.bin
```

- **Store** writes a text file to `.silt/memories/<key>`
- **Search** embeds your query and compares against all memories using cosine similarity
- **The embedding index** is cached locally and rebuilt automatically when memories change
- **Branching** just works — memories are files in git, so they follow the DAG

Memories support optional YAML frontmatter for tags:

```
---
tags: [auth, security]
created: 2025-03-15
---
The auth service uses JWT with RS256 signing.
Keys are rotated monthly via Vault.
```

## Agent integration

Silt is designed to be called by LLM coding agents. Add to your `CLAUDE.md` or equivalent:

```markdown
Before making changes, run:
  silt search "<what you're about to do>"

After learning something important, run:
  silt store <key> -m "<what you learned>"
```

Use `--json` for structured output:

```sh
silt search "deployment" --json
```

```json
{
  "results": [
    {"key": "deploy", "score": 0.92, "content": "Kubernetes via ArgoCD...", "tags": ["infra"]}
  ]
}
```

## Search flags

| Flag | Default | Description |
|------|---------|-------------|
| `--top-k` | 5 | Number of results |
| `--threshold` | 0.5 | Minimum similarity score |
| `--json` | off | JSON output |

## Building from source

Requires Rust and OCaml 5.3+.

```sh
just setup    # install deps, download model, build, test
just build    # build only
just test     # run all tests
just run -- search "query"
```

See the [design doc](docs/DESIGN.md) for architecture details.

## License

MIT
