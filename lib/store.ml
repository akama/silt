let rec ensure_dir path =
  if not (Sys.file_exists path) then begin
    ensure_dir (Filename.dirname path);
    Sys.mkdir path 0o755
  end

let init paths =
  let config = Config.make paths in
  ensure_dir config.silt_dir;
  ensure_dir config.cache_dir;
  Config.write_config config;
  (* Add cache dir to .gitignore *)
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
  end;
  config

(* Skill installation *)
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
