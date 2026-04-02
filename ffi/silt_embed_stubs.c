#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>
#include <string.h>

/* Rust FFI */
extern int silt_embed(const char *input, size_t input_len, float *output);
extern size_t silt_embed_dims(void);

CAMLprim value caml_silt_embed_dims(value unit) {
    CAMLparam1(unit);
    CAMLreturn(Val_int(silt_embed_dims()));
}

CAMLprim value caml_silt_embed(value v_text) {
    CAMLparam1(v_text);
    CAMLlocal1(v_arr);

    const char *text = String_val(v_text);
    size_t len = caml_string_length(v_text);
    size_t dims = silt_embed_dims();

    float *buf = (float *)malloc(dims * sizeof(float));
    if (!buf) caml_failwith("silt_embed: allocation failed");

    int rc = silt_embed(text, len, buf);
    if (rc != 0) {
        free(buf);
        caml_failwith("silt_embed: embedding failed");
    }

    v_arr = caml_alloc_float_array(dims);
    for (size_t i = 0; i < dims; i++) {
        Store_double_flat_field(v_arr, i, (double)buf[i]);
    }

    free(buf);
    CAMLreturn(v_arr);
}
