open Cmdliner

let load_config () =
  match Silt.Config.read_config () with
  | Some c -> c
  | None ->
    Printf.eprintf "Not initialized. Run 'silt init <paths...>' first.\n";
    exit 1

let prompt_yn msg =
  Printf.printf "%s [Y/n] " msg;
  flush stdout;
  let line =
    try Some (input_line stdin)
    with End_of_file -> None
  in
  match line with
  | None | Some "" | Some "y" | Some "Y" | Some "yes" -> true
  | _ -> false

(* --- init --- *)
let init_cmd =
  let doc = "Initialize silt to index the given paths." in
  let info = Cmd.info "init" ~doc in
  let paths_arg =
    Arg.(non_empty & pos_all string [] & info [] ~docv:"PATH"
           ~doc:"Directories or files to index.")
  in
  let no_skill_flag =
    Arg.(value & flag & info ["no-skill"]
           ~doc:"Skip installing the Claude Code skill file.")
  in
  let term =
    Term.(const (fun paths no_skill ->
      let bad = List.filter (fun p -> not (Sys.file_exists p)) paths in
      if bad <> [] then begin
        Printf.eprintf "Error: path(s) not found: %s\n" (String.concat ", " bad);
        exit 1
      end;
      let config = Silt.Store.init paths in
      Printf.printf "Initialized silt in %s/\n" config.silt_dir;
      Printf.printf "Indexing: %s\n" (String.concat ", " config.paths);
      if not no_skill then begin
        let tty = Unix.isatty Unix.stdin in
        let should_install =
          if tty then
            prompt_yn "Install Claude Code skill file (.claude/skills/silt/SKILL.md)?"
          else true
        in
        if should_install then
          match Silt.Store.install_skill () with
          | `Installed ->
            Printf.printf "Installed skill to .claude/skills/silt/SKILL.md\n"
          | `Already_current ->
            Printf.printf "Skill file already up to date\n"
          | `Skipped_modified ->
            Printf.printf "Skill file exists and has been modified, skipping\n"
      end)
    $ paths_arg $ no_skill_flag)
  in
  Cmd.v info term

(* --- search --- *)
let search_cmd =
  let doc = "Search indexed documents." in
  let info = Cmd.info "search" ~doc in
  let query_arg =
    Arg.(required & pos 0 (some string) None & info [] ~docv:"QUERY"
           ~doc:"Search query")
  in
  let top_k_arg =
    Arg.(value & opt int 5 & info ["top-k"] ~docv:"N"
           ~doc:"Number of results (default: 5)")
  in
  let threshold_arg =
    Arg.(value & opt float 0.3 & info ["threshold"] ~docv:"FLOAT"
           ~doc:"Minimum score (default: 0.3)")
  in
  let json_flag =
    Arg.(value & flag & info ["json"] ~doc:"Output as JSON")
  in
  let semantic_flag =
    Arg.(value & flag & info ["semantic"]
           ~doc:"Semantic search only (embeddings)")
  in
  let keyword_flag =
    Arg.(value & flag & info ["keyword"]
           ~doc:"Keyword search only (exact term matching)")
  in
  let term =
    Term.(const (fun query top_k threshold json semantic keyword ->
      if String.trim query = "" then begin
        Printf.eprintf "Error: search query cannot be empty.\n";
        exit 1
      end;
      let config = load_config () in
      let mode =
        if semantic && keyword then begin
          Printf.eprintf "Error: --semantic and --keyword cannot be used together.\n";
          exit 1
        end;
        if semantic then Silt.Search.Semantic
        else if keyword then Silt.Search.Keyword
        else Silt.Search.Hybrid
      in
      let results = Silt.Search.search config ~query ~mode ~top_k ~threshold in
      if json then begin
        Printf.printf "{\"results\": [\n";
        let n = List.length results in
        List.iteri
          (fun i (r : Silt.Search.result) ->
            let escape s =
              s
              |> String.split_on_char '"'  |> String.concat "\\\""
              |> String.split_on_char '\n' |> String.concat "\\n"
            in
            Printf.printf "  {\"file\": \"%s\", \"breadcrumb\": \"%s\", \"start_line\": %d, \"end_line\": %d, \"score\": %.2f, \"preview\": \"%s\"}%s\n"
              (escape r.file) (escape r.breadcrumb)
              r.start_line r.end_line r.score (escape r.preview)
              (if i < n - 1 then "," else ""))
          results;
        Printf.printf "]}\n"
      end else if results = [] then
        Printf.eprintf "No results found.\n"
      else
        List.iter
          (fun (r : Silt.Search.result) ->
            Printf.printf "%s:%d > %s  (%.2f)\n  %s\n"
              r.file r.start_line r.breadcrumb r.score r.preview)
          results)
    $ query_arg $ top_k_arg $ threshold_arg $ json_flag
    $ semantic_flag $ keyword_flag)
  in
  Cmd.v info term

(* --- rebuild --- *)
let rebuild_cmd =
  let doc = "Force-rebuild the search index." in
  let info = Cmd.info "rebuild" ~doc in
  let term =
    Term.(const (fun () ->
      let config = load_config () in
      let n = Silt.Search.rebuild config in
      let dims = Silt_ffi.Embed.dims () in
      Printf.printf "Indexed %d chunks (%d dims)\n" n dims)
    $ const ())
  in
  Cmd.v info term

(* --- status --- *)
let status_cmd =
  let doc = "Show index status." in
  let info = Cmd.info "status" ~doc in
  let term =
    Term.(const (fun () ->
      let config = load_config () in
      let files, chunks = Silt.Search.status config in
      Printf.printf "Paths:  %s\n" (String.concat ", " config.paths);
      Printf.printf "Files:  %d\n" files;
      Printf.printf "Chunks: %d\n" chunks;
      if files = 0 then
        Printf.printf "\nNo files found. Check that the configured paths contain .md or .txt files.\n"
      else if chunks = 0 then
        Printf.printf "\nNo chunks indexed. Run 'silt rebuild' to index.\n")
    $ const ())
  in
  Cmd.v info term

(* --- skill --- *)
let skill_cmd =
  let doc = "Print or install the LLM skill file." in
  let info = Cmd.info "skill" ~doc in
  let install_flag =
    Arg.(value & flag & info ["install"]
           ~doc:"Install to .claude/skills/silt/SKILL.md")
  in
  let force_flag =
    Arg.(value & flag & info ["force"]
           ~doc:"Overwrite even if the skill file has been modified")
  in
  let term =
    Term.(const (fun install force ->
      if install then begin
        if force then begin
          let path = Filename.concat
            (Filename.concat ".claude" (Filename.concat "skills" "silt"))
            "SKILL.md"
          in
          (if Sys.file_exists path then Sys.remove path);
          match Silt.Store.install_skill () with
          | `Installed ->
            Printf.printf "Installed skill to .claude/skills/silt/SKILL.md\n"
          | _ -> assert false
        end else
          match Silt.Store.install_skill () with
          | `Installed ->
            Printf.printf "Installed skill to .claude/skills/silt/SKILL.md\n"
          | `Already_current ->
            Printf.printf "Skill file already up to date\n"
          | `Skipped_modified ->
            Printf.printf "Skill file exists and has been modified, skipping\n";
            Printf.printf "  Run 'silt skill --install --force' to overwrite\n"
      end else
        print_string Silt.Store.skill_content)
    $ install_flag $ force_flag)
  in
  Cmd.v info term

(* --- main --- *)
let () =
  let doc = "Git-native semantic search over project docs" in
  let info = Cmd.info "silt" ~version:Version.v ~doc in
  let group =
    Cmd.group info
      [ init_cmd; search_cmd; rebuild_cmd; status_cmd; skill_cmd ]
  in
  exit (Cmd.eval group)
