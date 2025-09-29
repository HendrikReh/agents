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

(* Run all tests *)
let () =
  Printf.printf "Running agent tests...\n";
  test_memory_init ();
  test_memory_variables ();
  test_memory_completion ();
  test_parse_action_node ();
  test_parse_branch_node ();
  test_summary_excerpt ();
  Printf.printf "All tests passed! [[memory:586134]]\n"
