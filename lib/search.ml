type search_mode = Hybrid | Semantic | Keyword

type result = {
  file : string;
  breadcrumb : string;
  start_line : int;
  end_line : int;
  score : float;
  preview : string;
}

(* Index entry for a single chunk *)
type chunk_entry = {
  ce_file : string;
  ce_breadcrumb : string;
  ce_start_line : int;
  ce_end_line : int;
  ce_mtime : float;
  ce_embedding : float array;
  ce_tokens : string list;
  ce_body : string;
}

type index = {
  version : int;
  entries : chunk_entry list;
}

let index_version = 2

(* Tokenize text for keyword search *)
let tokenize text =
  let buf = Buffer.create 32 in
  let tokens = ref [] in
  String.iter (fun c ->
    if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') then
      Buffer.add_char buf c
    else if (c >= 'A' && c <= 'Z') then
      Buffer.add_char buf (Char.chr (Char.code c + 32))
    else begin
      if Buffer.length buf > 0 then begin
        tokens := Buffer.contents buf :: !tokens;
        Buffer.clear buf
      end
    end)
    text;
  if Buffer.length buf > 0 then
    tokens := Buffer.contents buf :: !tokens;
  !tokens

(* Binary serialization *)
let write_string oc s =
  output_binary_int oc (String.length s);
  output_string oc s

let read_string ic =
  let len = input_binary_int ic in
  let buf = Bytes.create len in
  really_input ic buf 0 len;
  Bytes.to_string buf

let write_float oc f =
  let bits = Int64.bits_of_float f in
  output_string oc (Printf.sprintf "%016Lx" bits)

let read_float ic =
  let buf = Bytes.create 16 in
  really_input ic buf 0 16;
  Int64.float_of_bits (Int64.of_string ("0x" ^ Bytes.to_string buf))

let write_float32 oc f =
  let bits = Int32.bits_of_float f in
  output_string oc (Printf.sprintf "%08lx" bits)

let read_float32 ic =
  let buf = Bytes.create 8 in
  really_input ic buf 0 8;
  Int32.float_of_bits (Int32.of_string ("0x" ^ Bytes.to_string buf))

let write_index path (idx : index) =
  let oc = open_out_bin path in
  output_binary_int oc idx.version;
  output_binary_int oc (List.length idx.entries);
  List.iter (fun e ->
    write_string oc e.ce_file;
    write_string oc e.ce_breadcrumb;
    output_binary_int oc e.ce_start_line;
    output_binary_int oc e.ce_end_line;
    write_float oc e.ce_mtime;
    let dims = Array.length e.ce_embedding in
    output_binary_int oc dims;
    Array.iter (write_float32 oc) e.ce_embedding;
    write_string oc e.ce_body)
    idx.entries;
  close_out oc

let read_index path : index option =
  if not (Sys.file_exists path) then None
  else
    try
      let ic = open_in_bin path in
      let version = input_binary_int ic in
      if version <> index_version then begin
        close_in ic;
        None (* version mismatch, trigger rebuild *)
      end else begin
        let n = input_binary_int ic in
        let entries = List.init n (fun _ ->
          let ce_file = read_string ic in
          let ce_breadcrumb = read_string ic in
          let ce_start_line = input_binary_int ic in
          let ce_end_line = input_binary_int ic in
          let ce_mtime = read_float ic in
          let dims = input_binary_int ic in
          let ce_embedding = Array.init dims (fun _ -> read_float32 ic) in
          let ce_body = read_string ic in
          let ce_tokens = tokenize ce_body in
          { ce_file; ce_breadcrumb; ce_start_line; ce_end_line;
            ce_mtime; ce_embedding; ce_tokens; ce_body })
        in
        close_in ic;
        Some { version; entries }
      end
    with _ -> None

(* Build chunks + embeddings for a single file *)
let index_file (entry : Scanner.entry) =
  let ic = open_in entry.path in
  let content = In_channel.input_all ic in
  close_in ic;
  let chunks = Chunk.chunk_file entry.path content in
  List.map (fun (chunk : Chunk.t) ->
    let embedding = Silt_ffi.Embed.embed chunk.body in
    let ce_tokens = tokenize chunk.body in
    { ce_file = chunk.file;
      ce_breadcrumb = chunk.breadcrumb;
      ce_start_line = chunk.start_line;
      ce_end_line = chunk.end_line;
      ce_mtime = entry.mtime;
      ce_embedding = embedding;
      ce_tokens;
      ce_body = chunk.body })
    chunks

(* Incremental index update *)
let update_index (config : Config.t) =
  let index_path = Config.index_path config in
  let old_index = read_index index_path in
  let files = Scanner.scan config in

  (* Build map of old entries by file *)
  let old_by_file : (string, chunk_entry list) Hashtbl.t = Hashtbl.create 64 in
  let old_mtimes : (string, float) Hashtbl.t = Hashtbl.create 64 in
  (match old_index with
   | None -> ()
   | Some idx ->
     List.iter (fun e ->
       let prev = try Hashtbl.find old_by_file e.ce_file with Not_found -> [] in
       Hashtbl.replace old_by_file e.ce_file (e :: prev);
       Hashtbl.replace old_mtimes e.ce_file e.ce_mtime)
       idx.entries);

  let entries =
    List.concat_map (fun (file : Scanner.entry) ->
      match Hashtbl.find_opt old_mtimes file.path with
      | Some old_mtime when old_mtime = file.mtime ->
        (* Unchanged, reuse *)
        (match Hashtbl.find_opt old_by_file file.path with
         | Some chunks -> chunks
         | None -> index_file file)
      | _ ->
        (* New or modified *)
        index_file file)
      files
  in

  let idx = { version = index_version; entries } in
  (* Ensure cache dir exists *)
  let rec ensure_dir path =
    if not (Sys.file_exists path) then begin
      ensure_dir (Filename.dirname path);
      Sys.mkdir path 0o755
    end
  in
  ensure_dir config.cache_dir;
  write_index index_path idx;
  idx

let build_index (config : Config.t) =
  let files = Scanner.scan config in
  let entries = List.concat_map index_file files in
  let idx = { version = index_version; entries } in
  let rec ensure_dir path =
    if not (Sys.file_exists path) then begin
      ensure_dir (Filename.dirname path);
      Sys.mkdir path 0o755
    end
  in
  ensure_dir config.cache_dir;
  write_index (Config.index_path config) idx;
  idx

(* Scoring *)
let cosine_similarity a b =
  let n = Array.length a in
  let dot = ref 0.0 in
  for i = 0 to n - 1 do
    dot := !dot +. (a.(i) *. b.(i))
  done;
  !dot

let keyword_score query_tokens chunk_tokens =
  if query_tokens = [] then 0.0
  else
    let chunk_set = Hashtbl.create (List.length chunk_tokens) in
    List.iter (fun t -> Hashtbl.replace chunk_set t true) chunk_tokens;
    let matched = List.filter (fun qt -> Hashtbl.mem chunk_set qt) query_tokens in
    let distinct = List.sort_uniq String.compare matched in
    float_of_int (List.length distinct) /. float_of_int (List.length query_tokens)

let preview_text body =
  let maxlen = 80 in
  let first_line =
    match String.split_on_char '\n' body with
    | l :: _ -> String.trim l
    | [] -> ""
  in
  if String.length first_line > maxlen then
    String.sub first_line 0 maxlen ^ "..."
  else first_line

let search config ~query ~mode ~top_k ~threshold =
  let idx = update_index config in
  let query_tokens = tokenize query in

  let query_embedding = lazy (Silt_ffi.Embed.embed query) in

  let scored =
    List.filter_map (fun entry ->
      let sem_score = match mode with
        | Keyword -> 0.0
        | _ -> cosine_similarity (Lazy.force query_embedding) entry.ce_embedding
      in
      let kw_score = match mode with
        | Semantic -> 0.0
        | _ -> keyword_score query_tokens entry.ce_tokens
      in
      let score = match mode with
        | Semantic -> sem_score
        | Keyword -> kw_score
        | Hybrid -> 0.7 *. sem_score +. 0.3 *. kw_score
      in
      if score >= threshold then
        Some { file = entry.ce_file;
               breadcrumb = entry.ce_breadcrumb;
               start_line = entry.ce_start_line;
               end_line = entry.ce_end_line;
               score;
               preview = preview_text entry.ce_body }
      else None)
      idx.entries
  in
  let sorted = List.sort (fun a b -> Float.compare b.score a.score) scored in
  let rec take n = function
    | [] -> []
    | _ when n <= 0 -> []
    | x :: rest -> x :: take (n - 1) rest
  in
  take top_k sorted

let rebuild config =
  let idx = build_index config in
  List.length idx.entries

let status config =
  let idx = update_index config in
  let files = Hashtbl.create 16 in
  List.iter (fun e -> Hashtbl.replace files e.ce_file true) idx.entries;
  (Hashtbl.length files, List.length idx.entries)
