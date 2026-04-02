(** A single memory entry. *)
type t = {
  key : string;
  content : string;
  tags : string list;
  created : string option;
}

(** Parse a memory file's content into structured form. *)
val parse : key:string -> string -> t

(** Serialize a memory to file content (with frontmatter if tags/created present). *)
val serialize : t -> string

(** Strip YAML frontmatter, return just the body text. *)
val body : t -> string
