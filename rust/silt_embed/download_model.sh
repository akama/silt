#!/bin/bash
set -euo pipefail

MODEL_DIR="$(dirname "$0")/model"
mkdir -p "$MODEL_DIR"

BASE_URL="https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main"

echo "Downloading all-MiniLM-L6-v2 model files..."
curl -sL -o "$MODEL_DIR/model.safetensors" "$BASE_URL/model.safetensors"
curl -sL -o "$MODEL_DIR/tokenizer.json" "$BASE_URL/tokenizer.json"
curl -sL -o "$MODEL_DIR/config.json" "$BASE_URL/config.json"

echo "Done. Files in $MODEL_DIR:"
ls -lh "$MODEL_DIR"
