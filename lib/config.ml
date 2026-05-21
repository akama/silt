type t = {
  silt_dir : string;
  cache_dir : string;
  paths : string list;
  extensions : string list;
  exclude : string list;
}

let default_silt_dir = ".silt"
let default_extensions = [".md"; ".txt"]
let default_exclude = ["_build"; ".git"; ".jj"; "node_modules"; ".silt"]

let config_path silt_dir = Filename.concat silt_dir "config"

let make ?(silt_dir = default_silt_dir) ?(extensions = default_extensions)
    ?(exclude = default_exclude) paths =
  {
    silt_dir;
    cache_dir = Filename.concat silt_dir ".cache";
    paths;
    extensions;
    exclude;
  }

let index_path config =
  Filename.concat config.cache_dir "index.bin"

(* YAML serialization *)
let write_config config =
  let buf = Buffer.create 256 in
  Buffer.add_string buf "paths:\n";
  List.iter (fun p -> Buffer.add_string buf (Printf.sprintf "  - %s\n" p)) config.paths;
  Buffer.add_string buf "extensions:\n";
  List.iter (fun e -> Buffer.add_string buf (Printf.sprintf "  - %s\n" e)) config.extensions;
  Buffer.add_string buf "exclude:\n";
  List.iter (fun e -> Buffer.add_string buf (Printf.sprintf "  - %s\n" e)) config.exclude;
  let path = config_path config.silt_dir in
  let oc = open_out path in
  output_string oc (Buffer.contents buf);
  close_out oc

let read_config ?(silt_dir = default_silt_dir) () =
  let path = config_path silt_dir in
  if not (Sys.file_exists path) then None
  else
    try
      let ic = open_in path in
      let content = In_channel.input_all ic in
      close_in ic;
      let yaml = Yaml.of_string_exn content in
      let get_string_list key pairs =
        match List.assoc_opt key pairs with
        | Some (`A lst) ->
          List.filter_map (fun v -> match v with `String s -> Some s | _ -> None) lst
        | _ -> []
      in
      match yaml with
      | `O pairs ->
        let paths = get_string_list "paths" pairs in
        let extensions =
          match get_string_list "extensions" pairs with
          | [] -> default_extensions
          | l -> l
        in
        let exclude =
          match get_string_list "exclude" pairs with
          | [] -> default_exclude
          | l -> l
        in
        Some (make ~silt_dir ~extensions ~exclude paths)
      | _ -> None
    with _ -> None
