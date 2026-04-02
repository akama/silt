(** Initialize silt in the current directory. *)
val init : Config.t -> unit

(** Store a memory. Overwrites if key exists. *)
val store : Config.t -> key:string -> content:string -> unit

(** Get a memory by exact key. *)
val get : Config.t -> key:string -> Memory.t option

(** Remove a memory. *)
val forget : Config.t -> key:string -> bool

(** List all memory keys. *)
val list_keys : Config.t -> string list

(** List all memories with content. *)
val list_all : Config.t -> Memory.t list
