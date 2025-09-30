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

(* Mock OpenAI client for testing *)
module Mock_client = struct
  type response_fn = messages:Openai_client.Message.t list -> (string, string) result Lwt.t

  type t = {
    mutable responses : response_fn list;
    mutable call_count : int;
  }

  let create responses = { responses; call_count = 0 }

  let chat ?(temperature = 0.2) ?(model = None) t ~messages =
    let _ = temperature in
    let _ = model in
    t.call_count <- t.call_count + 1;
    match t.responses with
    | [] -> Lwt.return_error "Mock client ran out of responses"
    | fn :: rest ->
        t.responses <- rest;
        fn ~messages

  let call_count t = t.call_count
end

(* Planner tests with mocks *)
let test_planner_valid_plan () =
  let mock_response ~messages:_ =
    let plan_json = {|
      {
        "plan": [
          {
            "type": "action",
            "id": "step1",
            "label": "Calculate result",
            "prompt": "What is 2 + 2?",
            "tool": "llm"
          },
          {
            "type": "finish",
            "id": "done",
            "summary": "Calculation complete"
          }
        ]
      }
    |} in
    Lwt.return_ok plan_json
  in
  let mock_client = Mock_client.create [mock_response] in
  let client = (Obj.magic mock_client : Openai_client.t) in
  let planner = Planner.create client in
  let memory = Memory.init "Test goal" in

  match Lwt_main.run (Planner.plan planner ~goal:"Test goal" ~memory) with
  | Error msg -> Printf.printf "Plan failed: %s\n" msg; assert false
  | Ok plan ->
      assert (List.length plan = 2);
      (match List.hd plan with
       | Nodes.Action action ->
           assert (action.id = "step1");
           assert (action.label = "Calculate result")
       | _ -> assert false);
      assert (Mock_client.call_count mock_client = 1)

let test_planner_with_code_fence () =
  let mock_response ~messages:_ =
    let response = {|
```json
{
  "plan": [
    {
      "type": "finish",
      "id": "done",
      "summary": "Done"
    }
  ]
}
```
    |} in
    Lwt.return_ok response
  in
  let mock_client = Mock_client.create [mock_response] in
  let client = (Obj.magic mock_client : Openai_client.t) in
  let planner = Planner.create client in
  let memory = Memory.init "Test goal" in

  match Lwt_main.run (Planner.plan planner ~goal:"Test" ~memory) with
  | Error msg -> Printf.printf "Plan failed: %s\n" msg; assert false
  | Ok plan ->
      assert (List.length plan = 1);
      assert (Mock_client.call_count mock_client = 1)

let test_planner_invalid_json () =
  let mock_response ~messages:_ =
    Lwt.return_ok "This is not valid JSON"
  in
  let mock_client = Mock_client.create [mock_response] in
  let client = (Obj.magic mock_client : Openai_client.t) in
  let planner = Planner.create client in
  let memory = Memory.init "Test goal" in

  match Lwt_main.run (Planner.plan planner ~goal:"Test" ~memory) with
  | Error msg ->
      assert (String.length msg > 0);
      assert (Mock_client.call_count mock_client = 1)
  | Ok _ -> assert false

(* Executor tests with mocks *)
let test_executor_action_node () =
  let mock_response ~messages:_ =
    Lwt.return_ok "The answer is 4"
  in
  let mock_client = Mock_client.create [mock_response] in
  let client = (Obj.magic mock_client : Openai_client.t) in
  let executor = Executor.create client in
  let memory = Memory.init "Calculate 2 + 2" in

  let action : Nodes.action = {
    id = "calc";
    label = "Calculate";
    prompt = "What is 2 + 2?";
    tool = Some "llm";
    save_as = None;
  } in
  let plan = [Nodes.Action action; Nodes.Finish { id = "done"; summary = Some "Complete" }] in

  match Lwt_main.run (Executor.execute executor plan ~memory ~goal:"Calculate 2 + 2") with
  | Error msg -> Printf.printf "Execute failed: %s\n" msg; assert false
  | Ok (final_memory, finished) ->
      assert finished;
      assert (Memory.iterations final_memory = 1);
      assert (Memory.last_result final_memory = Some "The answer is 4");
      (match Memory.get_variable final_memory "calc" with
       | Some (`String v) -> assert (v = "The answer is 4")
       | _ -> assert false);
      assert (Mock_client.call_count mock_client = 1)

let test_executor_branch_node () =
  let memory = Memory.init "Test branching" in
  Memory.set_variable_string memory "has_result" "yes";

  (* No LLM calls needed for branch evaluation *)
  let mock_client = Mock_client.create [] in
  let client = (Obj.magic mock_client : Openai_client.t) in
  let executor = Executor.create client in

  let branch : Nodes.branch = {
    id = "check";
    condition = Has_variable "has_result";
    if_true = [Finish { id = "success"; summary = Some "Found result" }];
    if_false = [Finish { id = "failure"; summary = Some "No result" }];
  } in
  let plan = [Nodes.Branch branch] in

  match Lwt_main.run (Executor.execute executor plan ~memory ~goal:"Test") with
  | Error msg -> Printf.printf "Execute failed: %s\n" msg; assert false
  | Ok (final_memory, finished) ->
      assert finished;
      (match Memory.status final_memory with
       | Memory.Completed answer -> assert (answer = "Found result")
       | _ -> assert false)

let test_executor_loop_node () =
  let mock_responses = [
    (fun ~messages:_ -> Lwt.return_ok "Iteration 1");
    (fun ~messages:_ -> Lwt.return_ok "Iteration 2");
  ] in
  let mock_client = Mock_client.create mock_responses in
  let client = (Obj.magic mock_client : Openai_client.t) in
  let executor = Executor.create ~default_loop_iterations:2 client in
  let memory = Memory.init "Test loop" in

  let action : Nodes.action = {
    id = "work";
    label = "Do work";
    prompt = "Process";
    tool = Some "llm";
    save_as = None;
  } in
  let loop : Nodes.loop = {
    id = "repeat";
    condition = Always;
    body = [Action action];
    max_iterations = Some 2;
  } in
  let plan = [Nodes.Loop loop; Nodes.Finish { id = "done"; summary = Some "Loop complete" }] in

  match Lwt_main.run (Executor.execute executor plan ~memory ~goal:"Test") with
  | Error msg -> Printf.printf "Execute failed: %s\n" msg; assert false
  | Ok (final_memory, finished) ->
      assert finished;
      assert (Mock_client.call_count mock_client = 2);
      (match Memory.status final_memory with
       | Memory.Completed _ -> ()
       | _ -> assert false)

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

(* Run all tests *)
let () =
  Printf.printf "Running agent tests...\n";

  (* Memory tests *)
  test_memory_init ();
  test_memory_variables ();
  test_memory_completion ();

  (* Node parsing tests *)
  test_parse_action_node ();
  test_parse_branch_node ();

  (* Tools tests *)
  test_summary_excerpt ();

  (* State persistence tests *)
  test_memory_serialization_roundtrip ();
  test_memory_status_serialization ();
  test_memory_save_load_file ();
  test_memory_load_nonexistent ();

  (* Planner tests *)
  test_planner_valid_plan ();
  test_planner_with_code_fence ();
  test_planner_invalid_json ();

  (* Executor tests *)
  test_executor_action_node ();
  test_executor_branch_node ();
  test_executor_loop_node ();
  test_executor_condition_evaluation ();

  Printf.printf "All tests passed!\n"