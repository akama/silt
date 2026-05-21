---
name: silt
description: Search project documentation. Use before making changes to check for existing knowledge about the subsystem you're working on.
---

# Silt — search project docs

You have access to `silt`, a semantic search tool that indexes markdown and text files in this repository.

## When to use

**Before making changes**, search for existing documentation:

```sh
silt search "what you're about to work on"
```

## Commands

```sh
silt search "<query>"              # hybrid search (semantic + keyword)
silt search "<query>" --semantic   # embedding similarity only
silt search "<query>" --keyword    # exact term matching only
silt search "<query>" --json       # structured output for parsing
silt search "<query>" --top-k 10   # more results (default: 5)
silt status                        # show indexed files and chunk count
silt rebuild                       # force reindex after doc changes
```

## How results look

```
docs/DESIGN.md:36 > Architecture > Rust FFI  (0.87)
  A staticlib crate exposing a C ABI. Model weights...
```

Results show file path, line number, heading breadcrumb, similarity score, and a preview.

## Tips

- Use `--keyword` when searching for specific identifiers, function names, or error messages
- Use `--semantic` when searching by concept ("how does auth work")
- Default hybrid mode combines both — usually the best choice
- Use `--json` when you need to parse results programmatically
