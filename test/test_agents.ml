open Agents

(* Test fixtures *)
let test_goal = "What is 2 + 2?"

(* Memory module tests *)
let test_memory_init () =
  let mem = Memory.init test_goal in
  assert (Memory.goal mem = test_goal);
  assert (Memory.status mem = Memory.In_progress);
  assert (Memory.iterations mem = 0);
  assert (Memory.last_result mem = None)

let test_memory_variables () =
  let mem = Memory.init test_goal in
  Memory.set_variable_string mem "test_key" "test_value";
  match Memory.get_variable mem "test_key" with
  | Some (`String v) -> assert (v = "test_value")
  | _ -> assert false

let test_memory_completion () =
  let mem = Memory.init test_goal in
  let answer = "The answer is 4" in
  Memory.mark_completed mem answer;
  assert (Memory.status mem = Memory.Completed answer);
  assert (Memory.get_answer mem = Some answer)

(* Node parsing tests *)
let test_parse_action_node () =
  let json = `Assoc [
    ("type", `String "action");
    ("id", `String "test_action");
    ("label", `String "Test Action");
    ("prompt", `String "Do something");
    ("tool", `String "llm")
  ] in
  match Nodes.node_of_yojson json with
  | Nodes.Action action ->
      assert (action.id = "test_action");
      assert (action.label = "Test Action");
      assert (action.prompt = "Do something");
      assert (action.tool = Some "llm")
  | _ -> assert false

let test_parse_branch_node () =
  let json = `Assoc [
    ("type", `String "branch");
    ("id", `String "test_branch");
    ("condition", `Assoc [
      ("type", `String "has_variable");
      ("key", `String "result")
    ]);
    ("if_true", `List []);
    ("if_false", `List [])
  ] in
  match Nodes.node_of_yojson json with
  | Nodes.Branch branch ->
      assert (branch.id = "test_branch");
      (match branch.condition with
       | Nodes.Has_variable key -> assert (key = "result")
       | _ -> assert false)
  | _ -> assert false

(* Tools module tests *)
let test_summary_excerpt () =
  let mem = Memory.init "Test goal with a very long description" in
  Memory.set_variable_string mem "key1" "value1";
  Memory.set_variable_string mem "key2" "value2";
  let summary = Tools.summary_excerpt mem in
  assert (String.length summary <= Tools.max_summary_length)

(* State persistence tests *)
let test_memory_serialization_roundtrip () =
  let mem = Memory.init "Test goal for serialization" in
  Memory.set_variable_string mem "key1" "value1";
  Memory.set_variable mem "key2" (`Int 42);
  Memory.set_variable mem "key3" (`List [ `String "a"; `String "b" ]);
  Memory.set_last_result mem "Last result text";
  Memory.bump_iteration mem;
  Memory.bump_iteration mem;

  (* Serialize and deserialize *)
  let json = Memory.to_yojson mem in
  match Memory.of_yojson json with
  | Error msg -> Printf.printf "Deserialization failed: %s\n" msg; assert false
  | Ok restored ->
      assert (Memory.goal restored = "Test goal for serialization");
      assert (Memory.iterations restored = 2);
      assert (Memory.last_result restored = Some "Last result text");
      (match Memory.get_variable restored "key1" with
       | Some (`String v) -> assert (v = "value1")
       | _ -> assert false);
      (match Memory.get_variable restored "key2" with
       | Some (`Int v) -> assert (v = 42)
       | _ -> assert false);
      (match Memory.get_variable restored "key3" with
       | Some (`List _) -> ()
       | _ -> assert false)

let test_memory_status_serialization () =
  let mem = Memory.init "Test status" in

  (* Test In_progress status *)
  let json1 = Memory.to_yojson mem in
  (match Memory.of_yojson json1 with
   | Ok restored -> assert (Memory.status restored = Memory.In_progress)
   | Error _ -> assert false);

  (* Test Completed status *)
  Memory.mark_completed mem "Test answer";
  let json2 = Memory.to_yojson mem in
  (match Memory.of_yojson json2 with
   | Ok restored ->
       (match Memory.status restored with
        | Memory.Completed answer -> assert (answer = "Test answer")
        | _ -> assert false)
   | Error _ -> assert false);

  (* Test Failed status *)
  let mem2 = Memory.init "Test failed" in
  Memory.mark_failed mem2 ~reason:"Test failure";
  let json3 = Memory.to_yojson mem2 in
  (match Memory.of_yojson json3 with
   | Ok restored ->
       (match Memory.status restored with
        | Memory.Failed reason -> assert (reason = "Test failure")
        | _ -> assert false)
   | Error _ -> assert false)

let test_memory_save_load_file () =
  let temp_file = Filename.temp_file "agent_test" ".json" in

  (* Create and save memory *)
  let mem = Memory.init "File persistence test" in
  Memory.set_variable_string mem "saved_var" "saved_value";
  Memory.bump_iteration mem;

  (match Memory.save_to_file mem temp_file with
   | Error msg -> Printf.printf "Save failed: %s\n" msg; assert false
   | Ok () -> ());

  (* Load and verify *)
  (match Memory.load_from_file temp_file with
   | Error msg -> Printf.printf "Load failed: %s\n" msg; assert false
   | Ok restored ->
       assert (Memory.goal restored = "File persistence test");
       assert (Memory.iterations restored = 1);
       (match Memory.get_variable restored "saved_var" with
        | Some (`String v) -> assert (v = "saved_value")
        | _ -> assert false));

  (* Clean up *)
  Sys.remove temp_file

let test_memory_load_nonexistent () =
  match Memory.load_from_file "/nonexistent/path/to/file.json" with
  | Error msg ->
      assert (String.length msg > 0);
      assert (String.starts_with ~prefix:"State file not found" msg)
  | Ok _ -> assert false

(* Executor condition evaluation tests (no LLM needed) *)
let test_executor_condition_evaluation () =
  let memory = Memory.init "Test conditions" in
  Memory.set_variable_string memory "key1" "value1";
  Memory.set_variable memory "key2" (`Int 42);

  (* Test Has_variable *)
  assert (Executor.evaluate_condition memory (Nodes.Has_variable "key1"));
  assert (not (Executor.evaluate_condition memory (Nodes.Has_variable "missing")));

  (* Test Not_has_variable *)
  assert (Executor.evaluate_condition memory (Nodes.Not_has_variable "missing"));
  assert (not (Executor.evaluate_condition memory (Nodes.Not_has_variable "key1")));

  (* Test Equals *)
  assert (Executor.evaluate_condition memory (Nodes.Equals { key = "key1"; value = "value1" }));
  assert (not (Executor.evaluate_condition memory (Nodes.Equals { key = "key1"; value = "wrong" })));

  (* Test Not *)
  assert (Executor.evaluate_condition memory (Nodes.Not (Nodes.Has_variable "missing")));
  assert (not (Executor.evaluate_condition memory (Nodes.Not (Nodes.Has_variable "key1"))))

(* Planner JSON extraction tests *)
let test_planner_strip_code_fence () =
  let with_fence = {|```json
{"key": "value"}
```|} in
  let stripped = Planner.strip_code_fence with_fence in
  assert (String.trim stripped = {|{"key": "value"}|});

  let without_fence = {|{"key": "value"}|} in
  let unchanged = Planner.strip_code_fence without_fence in
  assert (String.trim unchanged = without_fence)

let test_planner_extract_json () =
  let valid_json = {|{"plan": []}|} in
  (match Planner.extract_json_candidate valid_json with
   | Ok _json -> ()
   | Error msg -> Printf.printf "Failed to extract: %s\n" msg; assert false);

  let with_text = {|Some text before {"plan": []} some text after|} in
  (match Planner.extract_json_candidate with_text with
   | Ok _json -> ()
   | Error msg -> Printf.printf "Failed to extract: %s\n" msg; assert false);

  let invalid = {|not json at all|} in
  (match Planner.extract_json_candidate invalid with
   | Error _ -> ()
   | Ok _ -> assert false)

(* Run all tests *)
let () =
  Printf.printf "Running agent tests...\n";

  (* Memory tests *)
  Printf.printf "  test_memory_init...";
  test_memory_init ();
  Printf.printf " OK\n";

  Printf.printf "  test_memory_variables...";
  test_memory_variables ();
  Printf.printf " OK\n";

  Printf.printf "  test_memory_completion...";
  test_memory_completion ();
  Printf.printf " OK\n";

  (* Node parsing tests *)
  Printf.printf "  test_parse_action_node...";
  test_parse_action_node ();
  Printf.printf " OK\n";

  Printf.printf "  test_parse_branch_node...";
  test_parse_branch_node ();
  Printf.printf " OK\n";

  (* Tools tests *)
  Printf.printf "  test_summary_excerpt...";
  test_summary_excerpt ();
  Printf.printf " OK\n";

  (* State persistence tests *)
  Printf.printf "  test_memory_serialization_roundtrip...";
  test_memory_serialization_roundtrip ();
  Printf.printf " OK\n";

  Printf.printf "  test_memory_status_serialization...";
  test_memory_status_serialization ();
  Printf.printf " OK\n";

  Printf.printf "  test_memory_save_load_file...";
  test_memory_save_load_file ();
  Printf.printf " OK\n";

  Printf.printf "  test_memory_load_nonexistent...";
  test_memory_load_nonexistent ();
  Printf.printf " OK\n";

  (* Executor tests (no mocks) *)
  Printf.printf "  test_executor_condition_evaluation...";
  test_executor_condition_evaluation ();
  Printf.printf " OK\n";

  (* Planner tests (no mocks) *)
  Printf.printf "  test_planner_strip_code_fence...";
  test_planner_strip_code_fence ();
  Printf.printf " OK\n";

  Printf.printf "  test_planner_extract_json...";
  test_planner_extract_json ();
  Printf.printf " OK\n";

  Printf.printf "All tests passed!\n"