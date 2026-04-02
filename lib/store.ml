let ensure_dir path =
  if not (Sys.file_exists path) then
    Sys.mkdir path 0o755

let init (config : Config.t) =
  ensure_dir config.root_dir;
  ensure_dir config.memory_dir;
  ensure_dir config.cache_dir;
  (* Add .cache to .gitignore if not already present *)
  let gitignore = ".gitignore" in
  let entry = Printf.sprintf "%s/" config.cache_dir in
  let already =
    if Sys.file_exists gitignore then
      let ic = open_in gitignore in
      let content = In_channel.input_all ic in
      close_in ic;
      String.split_on_char '\n' content
      |> List.exists (fun line -> String.trim line = entry)
    else false
  in
  if not already then begin
    let oc = open_out_gen [Open_append; Open_creat] 0o644 gitignore in
    Printf.fprintf oc "%s\n" entry;
    close_out oc
  end

let memory_path (config : Config.t) key =
  Filename.concat config.memory_dir key

let store (config : Config.t) ~key ~content =
  ensure_dir config.root_dir;
  ensure_dir config.memory_dir;
  let path = memory_path config key in
  let oc = open_out path in
  output_string oc content;
  close_out oc

let get (config : Config.t) ~key =
  let path = memory_path config key in
  if Sys.file_exists path then begin
    let ic = open_in path in
    let content = In_channel.input_all ic in
    close_in ic;
    Some (Memory.parse ~key content)
  end else
    None

let forget (config : Config.t) ~key =
  let path = memory_path config key in
  if Sys.file_exists path then begin
    Sys.remove path;
    true
  end else
    false

let list_keys (config : Config.t) =
  if Sys.file_exists config.memory_dir then
    Sys.readdir config.memory_dir
    |> Array.to_list
    |> List.sort String.compare
  else
    []

let list_all (config : Config.t) =
  list_keys config
  |> List.filter_map (fun key -> get config ~key)
