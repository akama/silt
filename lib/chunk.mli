type t = {
  file : string;
  breadcrumb : string;
  start_line : int;
  end_line : int;
  body : string;
}

(** Chunk a file into searchable pieces. Markdown files get heading-aware
    splitting; other files get paragraph-based splitting. *)
val chunk_file : string -> string -> t list

(** Count words in a string. *)
val word_count : string -> int
