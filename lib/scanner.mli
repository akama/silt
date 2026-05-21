type entry = {
  path : string;
  mtime : float;
}

(** Scan configured paths for indexable files. *)
val scan : Config.t -> entry list
