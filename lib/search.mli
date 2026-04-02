type result = {
  key : string;
  score : float;
  content : string;
  tags : string list;
}

(** Search memories by semantic similarity. *)
val search :
  Config.t ->
  query:string ->
  top_k:int ->
  threshold:float ->
  result list

(** Force rebuild the embedding index. Returns number of memories embedded. *)
val rebuild : Config.t -> int
