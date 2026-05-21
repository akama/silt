# silt

Semantic search over your project docs. A single static binary with an embedded sentence transformer — no dependencies, no model downloads, no server.

Point silt at a folder of markdown or text files and search by meaning or keyword. Documents are chunked by heading, embedded locally, and searched via cosine similarity. The index updates incrementally.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/akama/silt/main/install.sh | sh
```

Or download manually from [releases](https://github.com/akama/silt/releases/latest):

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

Re-run the install script to update. Set `SILT_INSTALL_DIR` to change the install location (default: `/usr/local/bin`).

Linux binaries are fully static (musl) and run on any distro.

## Quick start

```sh
silt init docs/                              # index a folder
silt search "how does authentication work"   # hybrid search
silt search "musl" --keyword                 # exact term matching
silt search "deploy process" --semantic      # embedding similarity
silt status                                  # show indexed files/chunks
silt rebuild                                 # force reindex
```

## How it works

```
docs/                    ← your existing markdown/text files
  DESIGN.md
  systems/
    auth.md
    deploy.md
.silt/
  config                 ← paths, extensions, excludes
  .cache/                ← gitignored, rebuilt on demand
    index.bin
```

- **Init** points silt at one or more directories
- **Search** chunks your docs by heading, embeds them, and finds the best matches
- **The index** updates incrementally — only changed files get re-embedded
- **Three modes**: hybrid (default), `--semantic` only, `--keyword` only

Results show file path, line number, and heading breadcrumb:

```
docs/systems/auth.md:15 > auth.md > Auth > JWT tokens  (0.87)
  Auth uses JWT RS256. Keys rotated monthly via Vault...
```

## Agent integration

Silt is designed to be called by LLM coding agents. Run `silt skill --install` to add a Claude Code skill, or add to your `CLAUDE.md`:

```markdown
Before making changes, run:
  silt search "<what you're about to do>"
```

Use `--json` for structured output:

```sh
silt search "deployment" --json
```

```json
{
  "results": [
    {"file": "docs/deploy.md", "breadcrumb": "deploy.md > Process", "start_line": 5, "end_line": 20, "score": 0.87, "preview": "Deploy via ArgoCD..."}
  ]
}
```

## Search flags

| Flag | Default | Description |
|------|---------|-------------|
| `--top-k` | 5 | Number of results |
| `--threshold` | 0.3 | Minimum score |
| `--semantic` | off | Embedding similarity only |
| `--keyword` | off | Exact term matching only |
| `--json` | off | JSON output |

## Building from source

Requires Rust and OCaml 5.3+.

```sh
just setup    # install deps, download model, build, test
just build    # build only
just test     # run all tests
just run -- search "query"
```

See [docs/systems/](docs/systems/) for architecture details.

## License

MIT
