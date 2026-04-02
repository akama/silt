type result = {
  key : string;
  score : float;
  content : string;
  tags : string list;
}

(* Index entry stored in the cache *)
type index_entry = {
  ie_key : string;
  ie_mtime : float;
  ie_embedding : float array;
}

type index = {
  entries : index_entry list;
}

(* Binary serialization for the index *)
let write_index path (idx : index) =
  let oc = open_out_bin path in
  let n = List.length idx.entries in
  output_binary_int oc n;
  List.iter
    (fun entry ->
      let key_bytes = Bytes.of_string entry.ie_key in
      output_binary_int oc (Bytes.length key_bytes);
      output_bytes oc key_bytes;
      let mtime_bits = Int64.bits_of_float entry.ie_mtime in
      output_string oc (Printf.sprintf "%016Lx" mtime_bits);
      let dims = Array.length entry.ie_embedding in
      output_binary_int oc dims;
      Array.iter
        (fun f ->
          let bits = Int32.bits_of_float f in
          output_string oc (Printf.sprintf "%08lx" bits))
        entry.ie_embedding)
    idx.entries;
  close_out oc

let read_hex_int32 ic =
  let buf = Bytes.create 8 in
  really_input ic buf 0 8;
  Int32.of_string ("0x" ^ Bytes.to_string buf)

let read_hex_int64 ic =
  let buf = Bytes.create 16 in
  really_input ic buf 0 16;
  Int64.of_string ("0x" ^ Bytes.to_string buf)

let read_index path : index option =
  if not (Sys.file_exists path) then None
  else
    try
      let ic = open_in_bin path in
      let n = input_binary_int ic in
      let entries =
        List.init n (fun _ ->
          let key_len = input_binary_int ic in
          let key_buf = Bytes.create key_len in
          really_input ic key_buf 0 key_len;
          let ie_key = Bytes.to_string key_buf in
          let ie_mtime = Int64.float_of_bits (read_hex_int64 ic) in
          let dims = input_binary_int ic in
          let ie_embedding =
            Array.init dims (fun _ -> Int32.float_of_bits (read_hex_int32 ic))
          in
          { ie_key; ie_mtime; ie_embedding })
      in
      close_in ic;
      Some { entries }
    with _ -> None

let file_mtime path =
  let stat = Unix.stat path in
  stat.Unix.st_mtime

let cosine_similarity a b =
  let n = Array.length a in
  let dot = ref 0.0 in
  for i = 0 to n - 1 do
    dot := !dot +. (a.(i) *. b.(i))
  done;
  !dot  (* vectors are already L2-normalized *)

let build_index (config : Config.t) : index =
  let memories = Store.list_all config in
  let entries =
    List.map
      (fun (mem : Memory.t) ->
        let path = Filename.concat config.memory_dir mem.key in
        let mtime = file_mtime path in
        let text = Memory.body mem in
        let embedding = Silt_ffi.Embed.embed text in
        { ie_key = mem.key; ie_mtime = mtime; ie_embedding = embedding })
      memories
  in
  { entries }

let update_index (config : Config.t) : index =
  let index_path = Config.index_path config in
  let old_index = read_index index_path in
  let current_keys = Store.list_keys config in
  (* Build a map from old index *)
  let old_map =
    match old_index with
    | None -> Hashtbl.create 0
    | Some idx ->
      let tbl = Hashtbl.create (List.length idx.entries) in
      List.iter (fun e -> Hashtbl.replace tbl e.ie_key e) idx.entries;
      tbl
  in
  let entries =
    List.map
      (fun key ->
        let path = Filename.concat config.memory_dir key in
        let mtime = file_mtime path in
        match Hashtbl.find_opt old_map key with
        | Some old_entry when old_entry.ie_mtime = mtime ->
          (* Unchanged, reuse embedding *)
          old_entry
        | _ ->
          (* New or modified, re-embed *)
          let mem =
            match Store.get config ~key with
            | Some m -> m
            | None -> failwith ("missing memory: " ^ key)
          in
          let text = Memory.body mem in
          let embedding = Silt_ffi.Embed.embed text in
          { ie_key = key; ie_mtime = mtime; ie_embedding = embedding })
      current_keys
  in
  let idx = { entries } in
  (* Ensure cache dir exists *)
  if not (Sys.file_exists config.cache_dir) then
    Sys.mkdir config.cache_dir 0o755;
  write_index index_path idx;
  idx

let search config ~query ~top_k ~threshold =
  let idx = update_index config in
  let query_emb = Silt_ffi.Embed.embed query in
  let scored =
    List.filter_map
      (fun entry ->
        let score = cosine_similarity query_emb entry.ie_embedding in
        if score >= threshold then
          let mem =
            match Store.get config ~key:entry.ie_key with
            | Some m -> m
            | None -> { Memory.key = entry.ie_key; content = ""; tags = []; created = None }
          in
          Some { key = entry.ie_key; score; content = mem.content; tags = mem.tags }
        else None)
      idx.entries
  in
  let sorted =
    List.sort (fun a b -> Float.compare b.score a.score) scored
  in
  let rec take n = function
    | [] -> []
    | _ when n <= 0 -> []
    | x :: rest -> x :: take (n - 1) rest
  in
  take top_k sorted

let rebuild config =
  let idx = build_index config in
  if not (Sys.file_exists config.cache_dir) then
    Sys.mkdir config.cache_dir 0o755;
  write_index (Config.index_path config) idx;
  List.length idx.entries
