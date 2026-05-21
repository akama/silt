# Chunking System

Silt splits documents into searchable chunks before embedding. The chunking strategy is format-aware: markdown files get heading-based splitting, while plain text files use paragraph-based splitting.

## Why chunk?

The embedding model (all-MiniLM-L6-v2) has a 512 token input limit. A typical markdown doc is thousands of tokens. Embedding the whole file would:

1. Truncate most of the content (only the first ~400 words get embedded)
2. Dilute the embedding — a vector representing an entire design doc is too vague to match specific queries

By chunking, each piece gets its own focused embedding. A search for "JWT authentication" matches the auth section, not the whole doc.

## Markdown chunking

The chunker makes a single pass over the file's lines, tracking state:

### Heading stack

A stack of `(level, text)` pairs tracks the current heading hierarchy. When a `## Subsection` is encountered, all headings at level 2+ are popped and the new one is pushed. This produces breadcrumbs like:

```
DESIGN.md > Architecture > Rust static library
```

### Flush rules

A new chunk is emitted when:

- A **new heading** is encountered (the heading starts the next chunk)
- The **word count exceeds 400** (split at the last paragraph break)
- **End of file** is reached

### Frontmatter

YAML frontmatter (the `---` delimited block at the top of a file) is stripped entirely. It's metadata, not searchable content.

### Code blocks

Fenced code blocks (triple backtick) flow into the current chunk. They are not split mid-block. If a code block alone exceeds 400 words, it becomes its own chunk.

### Large sections

When a section has no sub-headings and exceeds 400 words, `split_large_body` kicks in:

1. Split the body into paragraphs (on blank lines)
2. If any single paragraph exceeds 400 words, hard-split it by word count
3. Group paragraphs into chunks, each under 400 words

## Plain text chunking

For non-markdown files (`.txt`, etc.), the chunker uses paragraph-based splitting with the same 400-word cap. The breadcrumb is just the filename.

## Data structure

```ocaml
type t = {
  file : string;        (* relative path *)
  breadcrumb : string;  (* "file.md > H1 > H2 > H3" *)
  start_line : int;     (* 1-based, inclusive *)
  end_line : int;       (* 1-based, inclusive *)
  body : string;        (* the chunk text *)
}
```

## Edge cases

| Case | Handling |
|------|----------|
| Empty file | Zero chunks, silently skipped |
| No headings | Breadcrumb is just the filename |
| Binary file | Detected by null-byte check, skipped |
| File > 10k lines | Streaming chunker, no memory issue |
| Single huge paragraph | Hard-split at 400 words |
