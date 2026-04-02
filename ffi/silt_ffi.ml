module Embed = struct
  external dims : unit -> int = "caml_silt_embed_dims"
  external embed : string -> float array = "caml_silt_embed"

  let embed_batch texts = List.map embed texts
end
