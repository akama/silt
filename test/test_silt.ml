let starts_with s prefix =
  String.length s >= String.length prefix &&
  String.sub s 0 (String.length prefix) = prefix

let test_chunk_markdown_headings () =
  let content = {|# Title

Some intro text.

## Section A

Content of section A.

## Section B

Content of section B.

### Subsection B1

Details of B1.
|} in
  let chunks = Silt.Chunk.chunk_file "test.md" content in
  assert (List.length chunks >= 3);
  let c0 = List.nth chunks 0 in
  assert (c0.file = "test.md");
  (* Breadcrumb should contain the filename *)
  assert (starts_with c0.breadcrumb "test.md");
  Printf.printf "  PASS: chunk markdown headings (%d chunks)\n" (List.length chunks)

let test_chunk_frontmatter () =
  let content = {|---
tags: [test]
created: 2025-01-01
---
# Doc Title

Body text here.
|} in
  let chunks = Silt.Chunk.chunk_file "doc.md" content in
  (* Frontmatter should be stripped, not appear in any chunk *)
  List.iter (fun (c : Silt.Chunk.t) ->
    assert (not (starts_with (String.trim c.body) "tags:"));
    assert (not (starts_with (String.trim c.body) "---")))
    chunks;
  Printf.printf "  PASS: chunk frontmatter stripped (%d chunks)\n" (List.length chunks)

let test_chunk_plaintext () =
  let content = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph.\n" in
  let chunks = Silt.Chunk.chunk_file "notes.txt" content in
  assert (List.length chunks >= 1);
  let c0 = List.nth chunks 0 in
  assert (c0.file = "notes.txt");
  Printf.printf "  PASS: chunk plaintext (%d chunks)\n" (List.length chunks)

let test_chunk_large_section () =
  (* Generate a section with >400 words *)
  let words = List.init 500 (fun i -> Printf.sprintf "word%d" i) in
  let content = "# Big Section\n\n" ^ String.concat " " words ^ "\n" in
  let chunks = Silt.Chunk.chunk_file "big.md" content in
  assert (List.length chunks >= 2);
  Printf.printf "  PASS: chunk large section split (%d chunks)\n" (List.length chunks)

let test_chunk_code_block () =
  let content = {|# Code

Some text.

```rust
fn main() {
    println!("hello");
}
```

More text.
|} in
  let chunks = Silt.Chunk.chunk_file "code.md" content in
  (* Code block should be included in a chunk *)
  let has_code = List.exists (fun (c : Silt.Chunk.t) ->
    let body = c.body in
    try let _ = Str.search_forward (Str.regexp_string "println") body 0 in true
    with Not_found -> false)
    chunks
  in
  assert has_code;
  Printf.printf "  PASS: chunk code block (%d chunks)\n" (List.length chunks)

let test_chunk_empty () =
  let chunks = Silt.Chunk.chunk_file "empty.md" "" in
  assert (chunks = []);
  Printf.printf "  PASS: chunk empty file\n"

let test_tokenize () =
  let tokens = Silt.Search.tokenize "Hello World foo-bar BAZ_123" in
  assert (List.mem "hello" tokens);
  assert (List.mem "world" tokens);
  assert (List.mem "foo" tokens);
  assert (List.mem "bar" tokens);
  assert (List.mem "baz" tokens);
  assert (List.mem "123" tokens);
  Printf.printf "  PASS: tokenize\n"

let test_config_roundtrip () =
  let tmpdir = Filename.temp_dir "silt_test" "" in
  let silt_dir = Filename.concat tmpdir ".silt" in
  Sys.mkdir silt_dir 0o755;
  let config = Silt.Config.make ~silt_dir ["docs/"; "wiki/"] in
  Silt.Config.write_config config;
  let loaded = Silt.Config.read_config ~silt_dir () in
  (match loaded with
   | Some c ->
     assert (c.paths = ["docs/"; "wiki/"]);
     assert (c.extensions = Silt.Config.default_extensions)
   | None -> assert false);
  Printf.printf "  PASS: config roundtrip\n"

let test_scanner () =
  let tmpdir = Filename.temp_dir "silt_test" "" in
  let docs_dir = Filename.concat tmpdir "docs" in
  Sys.mkdir docs_dir 0o755;
  (* Create test files *)
  let write path content =
    let oc = open_out path in
    output_string oc content;
    close_out oc
  in
  write (Filename.concat docs_dir "a.md") "# Doc A\nContent A.";
  write (Filename.concat docs_dir "b.txt") "Some text.";
  write (Filename.concat docs_dir "c.py") "# not indexed";
  let config = Silt.Config.make [docs_dir] in
  let entries = Silt.Scanner.scan config in
  (* Should find a.md and b.txt but not c.py *)
  let paths = List.map (fun (e : Silt.Scanner.entry) -> Filename.basename e.path) entries in
  assert (List.mem "a.md" paths);
  assert (List.mem "b.txt" paths);
  assert (not (List.mem "c.py" paths));
  Printf.printf "  PASS: scanner (%d files)\n" (List.length entries)

let test_word_count () =
  assert (Silt.Chunk.word_count "hello world" = 2);
  assert (Silt.Chunk.word_count "" = 0);
  assert (Silt.Chunk.word_count "  one  " = 1);
  Printf.printf "  PASS: word_count\n"

let () =
  Printf.printf "Running silt tests...\n";
  test_word_count ();
  test_chunk_empty ();
  test_chunk_markdown_headings ();
  test_chunk_frontmatter ();
  test_chunk_plaintext ();
  test_chunk_large_section ();
  test_chunk_code_block ();
  test_tokenize ();
  test_config_roundtrip ();
  test_scanner ();
  Printf.printf "All tests passed!\n"
