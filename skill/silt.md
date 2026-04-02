# Silt — project memory

You have access to `silt`, a semantic memory tool for this repository. Memories are plain text files stored in `.silt/memories/` and tracked by git.

## When to use

**Read before you write.** Before making changes to a subsystem, search for existing knowledge:

```sh
silt search "what you're about to work on"
```

**Save what you learn.** After discovering something non-obvious — conventions, gotchas, architectural decisions, tribal knowledge — store it:

```sh
silt store <key> -m "what you learned"
```

**Don't store things derivable from code.** Function signatures, file paths, and git history don't need to be memorized. Store the *why*, not the *what*.

## Commands

```sh
silt search "<query>"              # semantic search (top 5, threshold 0.5)
silt search "<query>" --json       # structured output for parsing
silt store <key> -m "<content>"    # save a memory (overwrites if key exists)
silt get <key>                     # retrieve by exact key
silt list                          # list all keys
silt list --long                   # list keys with content preview
silt forget <key>                  # delete a memory
```

## Key naming

Use short, descriptive, kebab-case keys: `auth-jwt`, `db-migrations`, `ci-deploy-flow`, `error-handling`. The key is the filename — keep it greppable.

## Tags

Add YAML frontmatter when storing via stdin for richer metadata:

```sh
cat <<'EOF' | silt store auth-jwt
---
tags: [auth, security]
created: 2025-03-15
---
JWT RS256 tokens. Keys rotated monthly via Vault.
Refresh tokens stored server-side in Redis (30-day TTL).
EOF
```

## Good memories

- Architectural decisions and their rationale
- Non-obvious conventions ("we use X instead of Y because...")
- Integration details (API contracts, auth flows, data formats)
- Operational knowledge (deploy process, incident patterns)
- Project-specific gotchas and workarounds

## Bad memories

- Code that can be read directly
- Things that change frequently (use the code as source of truth)
- Personal preferences or style opinions
- Duplicates of documentation that already exists
