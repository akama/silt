let rec ensure_dir_rec path =
  if not (Sys.file_exists path) then begin
    ensure_dir_rec (Filename.dirname path);
    Sys.mkdir path 0o755
  end

let ensure_dir = ensure_dir_rec

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
  ensure_dir (Filename.dirname path);
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
  let rec walk prefix dir =
    if Sys.file_exists dir then
      Sys.readdir dir
      |> Array.to_list
      |> List.concat_map (fun name ->
        let path = Filename.concat dir name in
        let key = if prefix = "" then name else prefix ^ "/" ^ name in
        if Sys.is_directory path then
          walk key path
        else
          [key])
    else
      []
  in
  walk "" config.memory_dir |> List.sort String.compare

let list_all (config : Config.t) =
  list_keys config
  |> List.filter_map (fun key -> get config ~key)

let skill_content = Skill_content.text

let skill_dir = Filename.concat ".claude" (Filename.concat "skills" "silt")
let skill_path = Filename.concat skill_dir "SKILL.md"

let install_skill () =
  if Sys.file_exists skill_path then begin
    let ic = open_in skill_path in
    let existing = In_channel.input_all ic in
    close_in ic;
    if existing = skill_content then
      `Already_current
    else
      `Skipped_modified
  end else begin
    ensure_dir skill_dir;
    let oc = open_out skill_path in
    output_string oc skill_content;
    close_out oc;
    `Installed
  end
