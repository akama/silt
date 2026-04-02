let test_memory_parse_plain () =
  let raw = "Use dune build @fmt before committing." in
  let mem = Silt.Memory.parse ~key:"formatting" raw in
  assert (mem.key = "formatting");
  assert (mem.content = "Use dune build @fmt before committing.");
  assert (mem.tags = []);
  assert (mem.created = None);
  Printf.printf "  PASS: parse plain text\n"

let test_memory_parse_frontmatter () =
  let raw = {|---
tags: [auth, security]
created: 2025-03-15
---
Auth uses JWT RS256.|} in
  let mem = Silt.Memory.parse ~key:"auth" raw in
  assert (mem.key = "auth");
  assert (mem.content = "Auth uses JWT RS256.");
  assert (mem.tags = ["auth"; "security"]);
  assert (mem.created = Some "2025-03-15");
  Printf.printf "  PASS: parse frontmatter\n"

let test_memory_serialize_plain () =
  let mem = Silt.Memory.{ key = "test"; content = "hello"; tags = []; created = None } in
  let s = Silt.Memory.serialize mem in
  assert (s = "hello");
  Printf.printf "  PASS: serialize plain\n"

let test_memory_serialize_with_meta () =
  let mem = Silt.Memory.{ key = "test"; content = "hello"; tags = ["a"; "b"]; created = Some "2025-01-01" } in
  let s = Silt.Memory.serialize mem in
  assert (String.length s > 0);
  (* Should contain frontmatter markers *)
  assert (String.sub s 0 3 = "---");
  Printf.printf "  PASS: serialize with metadata\n"

let test_memory_roundtrip () =
  let original = Silt.Memory.{ key = "rt"; content = "test content"; tags = ["x"]; created = Some "2025-06-01" } in
  let serialized = Silt.Memory.serialize original in
  let parsed = Silt.Memory.parse ~key:"rt" serialized in
  assert (parsed.content = original.content);
  assert (parsed.tags = original.tags);
  assert (parsed.created = original.created);
  Printf.printf "  PASS: roundtrip\n"

let test_store_operations () =
  let tmpdir = Filename.temp_dir "silt_test" "" in
  let config = Silt.Config.make (Filename.concat tmpdir ".silt") in
  Silt.Store.init config;
  (* Store *)
  Silt.Store.store config ~key:"k1" ~content:"value1";
  Silt.Store.store config ~key:"k2" ~content:"value2";
  (* List *)
  let keys = Silt.Store.list_keys config in
  assert (keys = ["k1"; "k2"]);
  (* Get *)
  (match Silt.Store.get config ~key:"k1" with
   | Some mem -> assert (mem.content = "value1")
   | None -> assert false);
  (* Get missing *)
  assert (Silt.Store.get config ~key:"missing" = None);
  (* Forget *)
  assert (Silt.Store.forget config ~key:"k1" = true);
  assert (Silt.Store.forget config ~key:"k1" = false);
  assert (Silt.Store.list_keys config = ["k2"]);
  (* Overwrite *)
  Silt.Store.store config ~key:"k2" ~content:"updated";
  (match Silt.Store.get config ~key:"k2" with
   | Some mem -> assert (mem.content = "updated")
   | None -> assert false);
  Printf.printf "  PASS: store operations\n"

let () =
  Printf.printf "Running silt tests...\n";
  test_memory_parse_plain ();
  test_memory_parse_frontmatter ();
  test_memory_serialize_plain ();
  test_memory_serialize_with_meta ();
  test_memory_roundtrip ();
  test_store_operations ();
  Printf.printf "All tests passed!\n"
