# Search System

Silt supports three search modes: hybrid (default), semantic-only, and keyword-only. Results include file paths, line numbers, heading breadcrumbs, and similarity scores.

## Hybrid search

The default mode combines semantic similarity with keyword matching:

```
score = 0.7 * semantic_score + 0.3 * keyword_score
```

This works well for most queries. Semantic search handles conceptual questions ("how does deployment work") while keyword search catches exact terms ("BertModel", "musl-gcc").

## Semantic search

Embeds the query using the same model that embedded the chunks, then computes cosine similarity against all chunk embeddings. Since vectors are L2-normalized, this is just a dot product.

Strengths:
- Understands synonyms and paraphrases
- "authentication" matches chunks about "JWT tokens" and "login flow"
- Language-agnostic similarity

Weaknesses:
- Can miss exact identifier matches if the term is rare in the training data
- Slower than keyword (requires embedding the query, ~10-50ms)

## Keyword search

Tokenizes the query and each chunk body on non-alphanumeric boundaries, lowercased. The score is:

```
keyword_score = distinct_query_tokens_matched / total_query_tokens
```

For example, searching "musl static linking" (3 tokens):
- A chunk containing all three terms scores 1.0
- A chunk containing "musl" and "static" but not "linking" scores 0.67
- A chunk with none of the terms scores 0.0

Strengths:
- Fast (no embedding computation)
- Exact match for identifiers, error messages, specific names
- Deterministic

Weaknesses:
- No understanding of meaning ("auth" won't match "authentication")
- Sensitive to exact spelling

## Index structure

The index is a binary file at `.silt/.cache/index.bin` containing:

- Version byte (currently 2)
- Chunk count
- Per chunk: file path, breadcrumb, start/end lines, file mtime, 384-dim embedding, body text

The keyword index (inverted index from tokens to chunk IDs) is rebuilt from the stored body text on load. This takes <10ms for typical doc collections and avoids the complexity of serializing it.

## Incremental updates

The unit of invalidation is the **file**, not the chunk. When `search` or `rebuild` is called:

1. Scan configured paths for all indexable files with their mtimes
2. Load existing index
3. For each file:
   - **mtime matches**: reuse all existing chunks (no re-embedding)
   - **mtime changed or new file**: re-chunk and re-embed
   - **file deleted**: drop its chunks
4. Write updated index

This means editing one doc only re-embeds that doc's chunks. Searching a 100-file corpus after changing one file takes ~100ms instead of minutes.

## Staleness detection

The index is lazily updated on every `search` call. There is no background watcher. If you want to force a full rebuild (e.g., after changing the embedding model), use `silt rebuild`.

## Thresholds and tuning

| Parameter | Default | Flag |
|-----------|---------|------|
| Top-k results | 5 | `--top-k` |
| Minimum score | 0.3 | `--threshold` |
| Hybrid weight (semantic) | 0.7 | hardcoded |
| Hybrid weight (keyword) | 0.3 | hardcoded |

The default threshold of 0.3 is deliberately low to avoid hiding marginally relevant results. The top-k limit is more important for controlling output volume.
