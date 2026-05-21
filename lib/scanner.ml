type entry = {
  path : string;
  mtime : float;
}

let is_binary path =
  try
    let ic = open_in_bin path in
    let buf = Bytes.create 512 in
    let n = input ic buf 0 512 in
    close_in ic;
    let rec check i =
      if i >= n then false
      else if Bytes.get buf i = '\000' then true
      else check (i + 1)
    in
    check 0
  with _ -> true (* if we can't read it, skip it *)

let has_extension extensions path =
  match extensions with
  | [] -> true
  | exts -> List.exists (fun ext -> Filename.check_suffix path ext) exts

let is_excluded exclude path =
  List.exists (fun pat ->
    (* Simple substring match for directory names *)
    let components = String.split_on_char '/' path in
    List.exists (fun c -> c = pat) components
  ) exclude

let scan (config : Config.t) =
  let results = ref [] in
  let rec walk dir =
    if Sys.file_exists dir && Sys.is_directory dir then begin
      let entries = Sys.readdir dir in
      Array.iter (fun name ->
        let path = Filename.concat dir name in
        if not (is_excluded config.exclude path) then begin
          if Sys.is_directory path then
            walk path
          else if has_extension config.extensions path
                  && not (is_binary path) then begin
            let stat = Unix.stat path in
            results := { path; mtime = stat.Unix.st_mtime } :: !results
          end
        end)
        entries
    end
  in
  List.iter walk config.paths;
  List.sort (fun a b -> String.compare a.path b.path) !results
