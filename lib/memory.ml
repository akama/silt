type t = {
  key : string;
  content : string;
  tags : string list;
  created : string option;
}

let frontmatter_sep = "---"

let parse_frontmatter yaml_str =
  let tags = ref [] in
  let created = ref None in
  (try
     let yaml = Yaml.of_string_exn yaml_str in
     (match yaml with
      | `O pairs ->
        List.iter
          (fun (k, v) ->
            match (k, v) with
            | "tags", `A lst ->
              tags :=
                List.filter_map
                  (fun v ->
                    match v with `String s -> Some s | _ -> None)
                  lst
            | "created", `String s -> created := Some s
            | _ -> ())
          pairs
      | _ -> ())
   with _ -> ());
  (!tags, !created)

let parse ~key raw =
  let lines = String.split_on_char '\n' raw in
  match lines with
  | first :: rest when String.trim first = frontmatter_sep ->
    let rec split_fm acc = function
      | [] ->
        { key; content = raw; tags = []; created = None }
      | line :: rest when String.trim line = frontmatter_sep ->
        let fm_str = String.concat "\n" (List.rev acc) in
        let body = String.concat "\n" rest in
        let body = String.trim body in
        let tags, created = parse_frontmatter fm_str in
        { key; content = body; tags; created }
      | line :: rest -> split_fm (line :: acc) rest
    in
    split_fm [] rest
  | _ ->
    { key; content = String.trim raw; tags = []; created = None }

let serialize mem =
  let has_meta = mem.tags <> [] || mem.created <> None in
  if not has_meta then mem.content
  else
    let buf = Buffer.create 256 in
    Buffer.add_string buf "---\n";
    (if mem.tags <> [] then (
       Buffer.add_string buf "tags: [";
       Buffer.add_string buf (String.concat ", " mem.tags);
       Buffer.add_string buf "]\n"));
    (match mem.created with
     | Some d ->
       Buffer.add_string buf "created: ";
       Buffer.add_string buf d;
       Buffer.add_char buf '\n'
     | None -> ());
    Buffer.add_string buf "---\n";
    Buffer.add_string buf mem.content;
    Buffer.contents buf

let body mem = mem.content
