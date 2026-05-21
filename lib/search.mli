type search_mode = Hybrid | Semantic | Keyword

type result = {
  file : string;
  breadcrumb : string;
  start_line : int;
  end_line : int;
  score : float;
  preview : string;
}

(** Search chunks with the given mode. *)
val search :
  Config.t ->
  query:string ->
  mode:search_mode ->
  top_k:int ->
  threshold:float ->
  result list

(** Force rebuild the entire index. Returns number of chunks indexed. *)
val rebuild : Config.t -> int

(** Return index stats: (file_count, chunk_count). *)
val status : Config.t -> int * int

(** Tokenize text for keyword search (lowercase, split on non-alphanumeric). *)
val tokenize : string -> string list
