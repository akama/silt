open Cmdliner

let config = Silt.Config.default ()

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
  let doc = "Initialize silt in the current repository." in
  let info = Cmd.info "init" ~doc in
  let no_skill_flag =
    Arg.(value & flag & info ["no-skill"]
           ~doc:"Skip installing the Claude Code skill file.")
  in
  let term =
    Term.(const (fun no_skill ->
      Silt.Store.init config;
      Printf.printf "Initialized silt in %s/\n" config.root_dir;
      Printf.printf "Added %s/ to .gitignore\n" config.cache_dir;
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
            Printf.printf "Skill file exists and has been modified, skipping\n";
            Printf.printf "  Run 'silt skill --install --force' to overwrite\n"
      end)
    $ no_skill_flag)
  in
  Cmd.v info term

(* --- store --- *)
let store_cmd =
  let doc = "Store a memory." in
  let info = Cmd.info "store" ~doc in
  let key_arg =
    Arg.(required & pos 0 (some string) None & info [] ~docv:"KEY" ~doc:"Memory key")
  in
  let msg_arg =
    Arg.(value & opt (some string) None & info ["m"; "message"] ~docv:"TEXT"
           ~doc:"Memory content. If omitted, reads from stdin.")
  in
  let term =
    Term.(const (fun key msg ->
      let content =
        match msg with
        | Some m -> m
        | None -> In_channel.input_all stdin
      in
      Silt.Store.store config ~key ~content;
      Printf.printf "Stored memory: %s\n" key)
    $ key_arg $ msg_arg)
  in
  Cmd.v info term

(* --- get --- *)
let get_cmd =
  let doc = "Retrieve a memory by exact key." in
  let info = Cmd.info "get" ~doc in
  let key_arg =
    Arg.(required & pos 0 (some string) None & info [] ~docv:"KEY" ~doc:"Memory key")
  in
  let term =
    Term.(const (fun key ->
      match Silt.Store.get config ~key with
      | Some mem -> print_string (Silt.Memory.body mem)
      | None ->
        Printf.eprintf "No memory found: %s\n" key;
        exit 1)
    $ key_arg)
  in
  Cmd.v info term

(* --- forget --- *)
let forget_cmd =
  let doc = "Remove a memory." in
  let info = Cmd.info "forget" ~doc in
  let key_arg =
    Arg.(required & pos 0 (some string) None & info [] ~docv:"KEY" ~doc:"Memory key")
  in
  let term =
    Term.(const (fun key ->
      if Silt.Store.forget config ~key then
        Printf.printf "Removed memory: %s\n" key
      else begin
        Printf.eprintf "No memory found: %s\n" key;
        exit 1
      end)
    $ key_arg)
  in
  Cmd.v info term

(* --- list --- *)
let list_cmd =
  let doc = "List all memory keys." in
  let info = Cmd.info "list" ~doc in
  let long_flag =
    Arg.(value & flag & info ["long"] ~doc:"Show first line of content alongside key")
  in
  let tags_arg =
    Arg.(value & opt (some string) None & info ["tags"] ~docv:"TAG"
           ~doc:"Filter by tag")
  in
  let term =
    Term.(const (fun long tags_filter ->
      let memories = Silt.Store.list_all config in
      let memories =
        match tags_filter with
        | None -> memories
        | Some tag ->
          List.filter (fun (m : Silt.Memory.t) -> List.mem tag m.tags) memories
      in
      List.iter
        (fun (mem : Silt.Memory.t) ->
          if long then begin
            let first_line =
              match String.split_on_char '\n' mem.content with
              | line :: _ ->
                let maxlen = 60 in
                if String.length line > maxlen then
                  String.sub line 0 maxlen ^ "..."
                else line
              | [] -> ""
            in
            Printf.printf "%-30s %s\n" mem.key first_line
          end else
            Printf.printf "%s\n" mem.key)
        memories)
    $ long_flag $ tags_arg)
  in
  Cmd.v info term

(* --- search --- *)
let search_cmd =
  let doc = "Semantic search across all memories." in
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
    Arg.(value & opt float 0.5 & info ["threshold"] ~docv:"FLOAT"
           ~doc:"Minimum similarity score (default: 0.5)")
  in
  let json_flag =
    Arg.(value & flag & info ["json"] ~doc:"Output as JSON")
  in
  let term =
    Term.(const (fun query top_k threshold json ->
      let results = Silt.Search.search config ~query ~top_k ~threshold in
      if json then begin
        Printf.printf "{\"results\": [\n";
        let n = List.length results in
        List.iteri
          (fun i (r : Silt.Search.result) ->
            let tags_json =
              Printf.sprintf "[%s]"
                (String.concat ", "
                   (List.map (fun t -> Printf.sprintf "\"%s\"" t) r.tags))
            in
            (* Escape content for JSON *)
            let escaped =
              r.content
              |> String.split_on_char '"'
              |> String.concat "\\\""
              |> String.split_on_char '\n'
              |> String.concat "\\n"
            in
            Printf.printf "  {\"key\": \"%s\", \"score\": %.2f, \"content\": \"%s\", \"tags\": %s}%s\n"
              r.key r.score escaped tags_json
              (if i < n - 1 then "," else ""))
          results;
        Printf.printf "]}\n"
      end else
        List.iter
          (fun (r : Silt.Search.result) ->
            let preview =
              let maxlen = 50 in
              let first_line =
                match String.split_on_char '\n' r.content with
                | l :: _ -> l
                | [] -> ""
              in
              if String.length first_line > maxlen then
                String.sub first_line 0 maxlen ^ "..."
              else first_line
            in
            Printf.printf "%-20s (%.2f)  %s\n" r.key r.score preview)
          results)
    $ query_arg $ top_k_arg $ threshold_arg $ json_flag)
  in
  Cmd.v info term

(* --- rebuild --- *)
let rebuild_cmd =
  let doc = "Force-rebuild the embedding index." in
  let info = Cmd.info "rebuild" ~doc in
  let term =
    Term.(const (fun () ->
      let dims = Silt_ffi.Embed.dims () in
      let n = Silt.Search.rebuild config in
      Printf.printf "Embedded %d memories (%d dims)\n" n dims)
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
          (* Force: remove existing and reinstall *)
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
  let doc = "Git-native memory for LLM coding agents" in
  let info = Cmd.info "silt" ~version:Version.v ~doc in
  let group =
    Cmd.group info
      [ init_cmd; store_cmd; get_cmd; forget_cmd; list_cmd;
        search_cmd; rebuild_cmd; skill_cmd ]
  in
  exit (Cmd.eval group)
