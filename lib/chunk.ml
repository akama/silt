type t = {
  file : string;
  breadcrumb : string;
  start_line : int;
  end_line : int;
  body : string;
}

let max_words = 400

let word_count s =
  let in_word = ref false in
  let count = ref 0 in
  String.iter (fun c ->
    if c = ' ' || c = '\t' || c = '\n' || c = '\r' then
      in_word := false
    else if not !in_word then begin
      in_word := true;
      incr count
    end) s;
  !count

let heading_level line =
  let len = String.length line in
  let rec count i =
    if i < len && line.[i] = '#' then count (i + 1) else i
  in
  let n = count 0 in
  if n > 0 && n < len && line.[n] = ' ' then
    Some (n, String.trim (String.sub line (n + 1) (len - n - 1)))
  else
    None

let make_breadcrumb file stack =
  let parts = Filename.basename file :: List.rev_map snd stack in
  String.concat " > " parts

let is_frontmatter_sep line = String.trim line = "---"
let is_fence_start line =
  let s = String.trim line in
  String.length s >= 3 && String.sub s 0 3 = "```"

(* Split a large body at paragraph boundaries *)
let split_large_body body start_line =
  let paragraphs = ref [] in
  let current = Buffer.create 256 in
  let current_start = ref start_line in
  let line_num = ref start_line in
  let lines = String.split_on_char '\n' body in
  let flush () =
    let s = Buffer.contents current in
    if String.trim s <> "" then
      paragraphs := (s, !current_start, !line_num - 1) :: !paragraphs;
    Buffer.clear current;
    current_start := !line_num
  in
  List.iter (fun line ->
    if String.trim line = "" && word_count (Buffer.contents current) > 0 then begin
      Buffer.add_char current '\n';
      flush ()
    end else begin
      if Buffer.length current > 0 then Buffer.add_char current '\n';
      Buffer.add_string current line
    end;
    incr line_num)
    lines;
  flush ();
  let paragraphs = List.rev !paragraphs in
  (* Hard-split any single paragraph that exceeds max_words *)
  let paragraphs =
    List.concat_map (fun (text, s, e) ->
      let wc = word_count text in
      if wc <= max_words then [(text, s, e)]
      else begin
        (* Split by words into max_words-sized pieces *)
        let words_list = String.split_on_char ' ' text in
        let sub_chunks = ref [] in
        let buf = Buffer.create 512 in
        let count = ref 0 in
        List.iter (fun w ->
          if !count >= max_words && Buffer.length buf > 0 then begin
            sub_chunks := Buffer.contents buf :: !sub_chunks;
            Buffer.clear buf;
            count := 0
          end;
          if Buffer.length buf > 0 then Buffer.add_char buf ' ';
          Buffer.add_string buf w;
          incr count)
          words_list;
        if Buffer.length buf > 0 then
          sub_chunks := Buffer.contents buf :: !sub_chunks;
        let subs = List.rev !sub_chunks in
        let n = List.length subs in
        let lines_per = max 1 ((e - s + 1) / n) in
        List.mapi (fun i text ->
          let sub_s = s + i * lines_per in
          let sub_e = if i = n - 1 then e else sub_s + lines_per - 1 in
          (text, sub_s, sub_e))
          subs
      end)
      paragraphs
  in
  (* Group paragraphs into chunks under max_words *)
  let chunks = ref [] in
  let buf = Buffer.create 512 in
  let chunk_start = ref start_line in
  let chunk_end = ref start_line in
  List.iter (fun (text, s, e) ->
    if word_count (Buffer.contents buf) + word_count text > max_words
       && Buffer.length buf > 0 then begin
      chunks := (Buffer.contents buf, !chunk_start, !chunk_end) :: !chunks;
      Buffer.clear buf;
      chunk_start := s
    end;
    if Buffer.length buf > 0 then Buffer.add_char buf '\n';
    Buffer.add_string buf text;
    chunk_end := e)
    paragraphs;
  if Buffer.length buf > 0 then
    chunks := (Buffer.contents buf, !chunk_start, !chunk_end) :: !chunks;
  List.rev !chunks

let chunk_markdown file content =
  let lines = String.split_on_char '\n' content in
  let chunks = ref [] in
  let heading_stack : (int * string) list ref = ref [] in
  let buf = Buffer.create 512 in
  let buf_start = ref 1 in
  let line_num = ref 0 in
  let in_fence = ref false in
  let in_frontmatter = ref false in
  let seen_frontmatter = ref false in

  let flush_buf () =
    let body = String.trim (Buffer.contents buf) in
    if body <> "" then begin
      let breadcrumb = make_breadcrumb file !heading_stack in
      let wc = word_count body in
      if wc > max_words then begin
        let sub_chunks = split_large_body body !buf_start in
        List.iter (fun (sub_body, s, e) ->
          chunks := { file; breadcrumb; start_line = s; end_line = e;
                      body = String.trim sub_body } :: !chunks)
          sub_chunks
      end else
        chunks := { file; breadcrumb; start_line = !buf_start;
                    end_line = !line_num; body } :: !chunks
    end;
    Buffer.clear buf;
    buf_start := !line_num + 1
  in

  List.iter (fun line ->
    incr line_num;

    (* Frontmatter handling: skip --- block at start of file *)
    if !line_num = 1 && is_frontmatter_sep line && not !seen_frontmatter then begin
      in_frontmatter := true;
      seen_frontmatter := true
    end else if !in_frontmatter then begin
      if is_frontmatter_sep line then begin
        in_frontmatter := false;
        buf_start := !line_num + 1
      end
    end

    (* Fenced code block tracking *)
    else if is_fence_start line then begin
      in_fence := not !in_fence;
      if Buffer.length buf > 0 then Buffer.add_char buf '\n';
      Buffer.add_string buf line
    end

    else if !in_fence then begin
      if Buffer.length buf > 0 then Buffer.add_char buf '\n';
      Buffer.add_string buf line
    end

    (* Heading: flush current chunk, update stack *)
    else begin
      match heading_level line with
      | Some (level, text) ->
        flush_buf ();
        (* Pop headings at this level or deeper *)
        heading_stack := List.filter (fun (l, _) -> l < level) !heading_stack;
        heading_stack := (level, text) :: !heading_stack;
        buf_start := !line_num;
        (* Include the heading text in the chunk body for keyword search *)
        Buffer.add_string buf text
      | None ->
        if Buffer.length buf > 0 then Buffer.add_char buf '\n';
        Buffer.add_string buf line;
        (* Check if we've exceeded max_words mid-chunk *)
        if word_count (Buffer.contents buf) > max_words * 2 then
          flush_buf ()
    end)
    lines;

  (* Flush remaining *)
  flush_buf ();
  List.rev !chunks

let chunk_plaintext file content =
  let basename = Filename.basename file in
  let lines = String.split_on_char '\n' content in
  let chunks = ref [] in
  let buf = Buffer.create 256 in
  let buf_start = ref 1 in
  let line_num = ref 0 in
  let flush () =
    let body = String.trim (Buffer.contents buf) in
    if body <> "" then begin
      let wc = word_count body in
      if wc > max_words then begin
        (* Split oversized paragraphs *)
        let sub_chunks = split_large_body body !buf_start in
        List.iter (fun (sub_body, s, e) ->
          chunks := { file; breadcrumb = basename; start_line = s;
                      end_line = e; body = String.trim sub_body } :: !chunks)
          sub_chunks
      end else
        chunks := { file; breadcrumb = basename; start_line = !buf_start;
                    end_line = !line_num; body } :: !chunks
    end;
    Buffer.clear buf;
    buf_start := !line_num + 1
  in
  List.iter (fun line ->
    incr line_num;
    if String.trim line = "" then
      flush ()
    else begin
      if Buffer.length buf > 0 then Buffer.add_char buf '\n';
      Buffer.add_string buf line
    end)
    lines;
  flush ();
  List.rev !chunks

let chunk_file file content =
  if Filename.check_suffix file ".md" then
    chunk_markdown file content
  else
    chunk_plaintext file content
