# Embedding Engine

The embedding engine is a Rust static library (`libsilt_embed`) that provides sentence embedding via a C ABI. It is linked directly into the OCaml binary — no subprocess, no shared library, no model download at runtime.

## Model

We use **all-MiniLM-L6-v2**, a sentence transformer from the SBERT family:

- 384-dimensional output vectors
- 6 transformer layers, 12 attention heads
- ~87MB safetensors weights
- 512 token max input (longer inputs are truncated by the tokenizer)
- Trained on 1B+ sentence pairs for semantic similarity

The model weights, tokenizer, and config are embedded into the Rust binary at compile time via `include_bytes!`. This means the binary is self-contained — no files to manage at runtime.

## Inference Pipeline

1. **Tokenization**: Input text is tokenized using the HuggingFace `tokenizers` library (Rust). The tokenizer config (`tokenizer.json`) is baked in.
2. **Forward pass**: Token IDs and type IDs are fed through the BERT model using the `candle` framework (pure Rust, no ONNX runtime).
3. **Mean pooling**: The output token embeddings are averaged across the sequence dimension to produce a single 384-dim vector.
4. **L2 normalization**: The vector is normalized to unit length, so cosine similarity reduces to a dot product.

## C ABI

Two functions are exposed:

```c
// Returns the embedding dimensionality (384)
size_t silt_embed_dims(void);

// Embed a UTF-8 string into a float vector
// Returns 0 on success, -1 on error
int silt_embed(const char *input, size_t input_len, float *output);
```

The `output` buffer must be caller-allocated with at least 384 floats. The engine is thread-safe — the model is loaded lazily via `OnceLock` on first call and reused for all subsequent embeddings.

## Performance

On a modern CPU, embedding a single sentence takes ~10-50ms depending on length. The model runs on CPU only (no GPU support). For the typical silt use case (indexing a few hundred doc chunks), total embedding time is a few seconds.

The engine is initialized lazily. The first `silt_embed()` call loads the model (~200ms). Subsequent calls skip initialization.

## Build

```sh
cd rust/silt_embed
./download_model.sh          # fetch model files from HuggingFace
cargo build --release        # produces target/release/libsilt_embed.a
```

The static library is ~153MB (includes model weights). It is linked into the OCaml binary by dune via `-lsilt_embed` in the FFI library's `c_library_flags`.
