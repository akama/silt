type t = {
  root_dir : string;  (* .silt *)
  memory_dir : string;  (* .silt/memories *)
  cache_dir : string;  (* .silt/.cache *)
}

let default_root = ".silt"

let make root_dir =
  {
    root_dir;
    memory_dir = Filename.concat root_dir "memories";
    cache_dir = Filename.concat root_dir ".cache";
  }

let default () = make default_root

let index_path config =
  Filename.concat config.cache_dir "index.bin"
