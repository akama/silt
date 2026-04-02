use std::ffi::c_char;
use std::sync::OnceLock;

use candle_core::{Device, Tensor};
use candle_nn::VarBuilder;
use candle_transformers::models::bert::{BertModel, Config};
use tokenizers::Tokenizer;

const MODEL_BYTES: &[u8] = include_bytes!("../model/model.safetensors");
const TOKENIZER_BYTES: &[u8] = include_bytes!("../model/tokenizer.json");
const CONFIG_BYTES: &[u8] = include_bytes!("../model/config.json");

const EMBEDDING_DIM: usize = 384;

struct EmbedEngine {
    model: BertModel,
    tokenizer: Tokenizer,
}

static ENGINE: OnceLock<EmbedEngine> = OnceLock::new();

fn get_engine() -> &'static EmbedEngine {
    ENGINE.get_or_init(|| {
        let device = Device::Cpu;
        let config: Config = serde_json::from_slice(CONFIG_BYTES).expect("bad config");
        let vb = VarBuilder::from_buffered_safetensors(
            MODEL_BYTES.to_vec(),
            candle_core::DType::F32,
            &device,
        )
        .expect("bad model");
        let model = BertModel::load(vb, &config).expect("failed to load model");
        let tokenizer =
            Tokenizer::from_bytes(TOKENIZER_BYTES).expect("failed to load tokenizer");
        EmbedEngine { model, tokenizer }
    })
}

fn embed_text(text: &str) -> Result<Vec<f32>, String> {
    let engine = get_engine();
    let encoding = engine
        .tokenizer
        .encode(text, true)
        .map_err(|e| format!("tokenize error: {e}"))?;

    let ids = encoding.get_ids();
    let type_ids = encoding.get_type_ids();
    let device = Device::Cpu;

    let token_ids = Tensor::new(ids, &device)
        .map_err(|e| format!("tensor error: {e}"))?
        .unsqueeze(0)
        .map_err(|e| format!("unsqueeze error: {e}"))?;
    let type_ids = Tensor::new(type_ids, &device)
        .map_err(|e| format!("tensor error: {e}"))?
        .unsqueeze(0)
        .map_err(|e| format!("unsqueeze error: {e}"))?;

    let embeddings = engine
        .model
        .forward(&token_ids, &type_ids, None)
        .map_err(|e| format!("forward error: {e}"))?;

    // Mean pooling over token dimension
    let (_batch, seq_len, _hidden) = embeddings.dims3().map_err(|e| format!("dims error: {e}"))?;
    let sum = embeddings
        .sum(1)
        .map_err(|e| format!("sum error: {e}"))?;
    let mean = (sum / (seq_len as f64))
        .map_err(|e| format!("div error: {e}"))?;

    // L2 normalize
    let norm = mean
        .sqr()
        .and_then(|s| s.sum_all())
        .and_then(|s| s.sqrt())
        .map_err(|e| format!("norm error: {e}"))?;
    let normalized = mean
        .broadcast_div(&norm)
        .map_err(|e| format!("normalize error: {e}"))?;

    let result: Vec<f32> = normalized
        .squeeze(0)
        .map_err(|e| format!("squeeze error: {e}"))?
        .to_vec1()
        .map_err(|e| format!("to_vec error: {e}"))?;

    Ok(result)
}

/// Returns the embedding dimensionality (384).
#[unsafe(no_mangle)]
pub extern "C" fn silt_embed_dims() -> usize {
    EMBEDDING_DIM
}

/// Embed a string into a 384-dimensional float vector.
///
/// # Safety
/// - `input` must point to a valid UTF-8 string of `input_len` bytes.
/// - `output` must point to a caller-allocated buffer of at least 384 f32s.
///
/// Returns 0 on success, -1 on error.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn silt_embed(
    input: *const c_char,
    input_len: usize,
    output: *mut f32,
) -> i32 {
    if input.is_null() || output.is_null() {
        return -1;
    }
    let slice = unsafe { std::slice::from_raw_parts(input as *const u8, input_len) };
    let text = match std::str::from_utf8(slice) {
        Ok(s) => s,
        Err(_) => return -1,
    };
    match embed_text(text) {
        Ok(vec) => {
            if vec.len() != EMBEDDING_DIM {
                return -1;
            }
            unsafe {
                std::ptr::copy_nonoverlapping(vec.as_ptr(), output, EMBEDDING_DIM);
            }
            0
        }
        Err(_) => -1,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_embed_text() {
        let result = embed_text("hello world").unwrap();
        assert_eq!(result.len(), EMBEDDING_DIM);
        // Check it's normalized (L2 norm ≈ 1.0)
        let norm: f32 = result.iter().map(|x| x * x).sum::<f32>().sqrt();
        assert!((norm - 1.0).abs() < 0.01, "norm was {norm}");
    }

    #[test]
    fn test_similar_texts() {
        let v1 = embed_text("the cat sat on the mat").unwrap();
        let v2 = embed_text("a cat is sitting on a mat").unwrap();
        let v3 = embed_text("quantum chromodynamics in particle physics").unwrap();

        let sim_12: f32 = v1.iter().zip(&v2).map(|(a, b)| a * b).sum();
        let sim_13: f32 = v1.iter().zip(&v3).map(|(a, b)| a * b).sum();

        assert!(sim_12 > sim_13, "similar texts should have higher cosine sim");
    }
}
