open Agents

let test_goal = "What is 2 + 2?"

let status_testable =
  let pp fmt status =
    let text =
      match status with
      | Memory.In_progress -> "in_progress"
      | Memory.Completed _ -> "completed"
      | Memory.Failed _ -> "failed"
    in
    Format.pp_print_string fmt text
  in
  Alcotest.testable pp ( = )

let run_lwt_result_or_fail promise =
  match Lwt_main.run promise with
  | Ok value -> value
  | Error msg -> Alcotest.fail msg

let string_contains ~needle haystack =
  let needle_len = String.length needle in
  let haystack_len = String.length haystack in
  let rec scan idx =
    if idx + needle_len > haystack_len then
      false
    else if String.sub haystack idx needle_len = needle then
      true
    else
      scan (idx + 1)
  in
  scan 0

(* Memory module tests *)

let test_memory_init () =
  let mem = Memory.init test_goal in
  Alcotest.(check string) "goal" test_goal (Memory.goal mem);
  Alcotest.(check status_testable) "status" Memory.In_progress (Memory.status mem);
  Alcotest.(check int) "iterations" 0 (Memory.iterations mem);
  Alcotest.(check (option string)) "last_result" None (Memory.last_result mem)

let test_memory_variables () =
  let mem = Memory.init test_goal in
  Memory.set_variable_string mem "test_key" "test_value";
  match Memory.get_variable mem "test_key" with
  | Some (`String value) -> Alcotest.(check string) "variable" "test_value" value
  | _ -> Alcotest.fail "Expected string variable"

let test_memory_completion () =
  let mem = Memory.init test_goal in
  let answer = "The answer is 4" in
  Memory.mark_completed mem answer;
  (match Memory.status mem with
  | Memory.Completed stored -> Alcotest.(check string) "completed answer" answer stored
  | _ -> Alcotest.fail "Status should be completed");
  Alcotest.(check (option string)) "get_answer" (Some answer) (Memory.get_answer mem)

let test_memory_serialization_roundtrip () =
  let mem = Memory.init "Test goal for serialization" in
  Memory.set_variable_string mem "key1" "value1";
  Memory.set_variable mem "key2" (`Int 42);
  Memory.set_variable mem "key3" (`List [ `String "a"; `String "b" ]);
  Memory.set_last_result mem "Last result text";
  Memory.bump_iteration mem;
  Memory.bump_iteration mem;
  let json = Memory.to_yojson mem in
  match Memory.of_yojson json with
  | Error msg -> Alcotest.failf "Deserialization failed: %s" msg
  | Ok restored ->
      Alcotest.(check string) "goal" "Test goal for serialization" (Memory.goal restored);
      Alcotest.(check int) "iterations" 2 (Memory.iterations restored);
      Alcotest.(check (option string)) "last_result" (Some "Last result text") (Memory.last_result restored);
      (match Memory.get_variable restored "key1" with
      | Some (`String v) -> Alcotest.(check string) "key1" "value1" v
      | _ -> Alcotest.fail "Expected string for key1");
      (match Memory.get_variable restored "key2" with
      | Some (`Int v) -> Alcotest.(check int) "key2" 42 v
      | _ -> Alcotest.fail "Expected int for key2");
      (match Memory.get_variable restored "key3" with
      | Some (`List values) -> Alcotest.(check int) "key3 length" 2 (List.length values)
      | _ -> Alcotest.fail "Expected list for key3")

let test_memory_status_serialization () =
  let mem = Memory.init "Test status" in
  let json_in_progress = Memory.to_yojson mem in
  (match Memory.of_yojson json_in_progress with
  | Ok restored -> Alcotest.(check status_testable) "in_progress" Memory.In_progress (Memory.status restored)
  | Error _ -> Alcotest.fail "Deserialization should succeed");
  Memory.mark_completed mem "Test answer";
  let json_completed = Memory.to_yojson mem in
  (match Memory.of_yojson json_completed with
  | Ok restored -> (
      match Memory.status restored with
      | Memory.Completed answer -> Alcotest.(check string) "completed" "Test answer" answer
      | _ -> Alcotest.fail "Status should be completed")
  | Error _ -> Alcotest.fail "Deserialization should succeed");
  let mem_failed = Memory.init "Test failed" in
  Memory.mark_failed mem_failed ~reason:"Test failure";
  let json_failed = Memory.to_yojson mem_failed in
  match Memory.of_yojson json_failed with
  | Ok restored -> (
      match Memory.status restored with
      | Memory.Failed reason -> Alcotest.(check string) "failed" "Test failure" reason
      | _ -> Alcotest.fail "Status should be failed")
  | Error _ -> Alcotest.fail "Deserialization should succeed"

let test_memory_save_load_file () =
  let temp_file = Filename.temp_file "agent_test" ".json" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists temp_file then Sys.remove temp_file)
    (fun () ->
      let mem = Memory.init "File persistence test" in
      Memory.set_variable_string mem "saved_var" "saved_value";
      Memory.bump_iteration mem;
      (match Memory.save_to_file mem temp_file with
      | Ok () -> ()
      | Error msg -> Alcotest.failf "Save failed: %s" msg);
      match Memory.load_from_file temp_file with
      | Error msg -> Alcotest.failf "Load failed: %s" msg
      | Ok restored ->
          Alcotest.(check string) "goal" "File persistence test" (Memory.goal restored);
          Alcotest.(check int) "iterations" 1 (Memory.iterations restored);
          (match Memory.get_variable restored "saved_var" with
          | Some (`String v) -> Alcotest.(check string) "saved_var" "saved_value" v
          | _ -> Alcotest.fail "Expected saved_var"))

let test_memory_load_nonexistent () =
  match Memory.load_from_file "/nonexistent/path/to/file.json" with
  | Error msg ->
      Alcotest.(check bool) "message" true (String.starts_with ~prefix:"State file not found" msg)
  | Ok _ -> Alcotest.fail "Expected load to fail"

(* Node parsing tests *)

let test_parse_action_node () =
  let json =
    `Assoc
      [
        ("type", `String "action");
        ("id", `String "test_action");
        ("label", `String "Test Action");
        ("prompt", `String "Do something");
        ("tool", `String "llm");
      ]
  in
  match Nodes.node_of_yojson json with
  | Nodes.Action action ->
      Alcotest.(check string) "id" "test_action" action.Nodes.id;
      Alcotest.(check string) "label" "Test Action" action.Nodes.label;
      Alcotest.(check string) "prompt" "Do something" action.Nodes.prompt;
      Alcotest.(check (option string)) "tool" (Some "llm") action.Nodes.tool
  | _ -> Alcotest.fail "Expected action node"

let test_parse_branch_node () =
  let json =
    `Assoc
      [
        ("type", `String "branch");
        ("id", `String "test_branch");
        ("condition", `Assoc [ ("type", `String "has_variable"); ("key", `String "result") ]);
        ("if_true", `List []);
        ("if_false", `List []);
      ]
  in
  match Nodes.node_of_yojson json with
  | Nodes.Branch branch -> (
      Alcotest.(check string) "branch id" "test_branch" branch.Nodes.id;
      match branch.Nodes.condition with
      | Nodes.Has_variable key -> Alcotest.(check string) "branch key" "result" key
      | _ -> Alcotest.fail "Expected has_variable condition")
  | _ -> Alcotest.fail "Expected branch node"

(* Nodes / executor tests *)

let test_executor_condition_evaluation () =
  let memory = Memory.init "Test conditions" in
  Memory.set_variable_string memory "key1" "value1";
  Memory.set_variable memory "key2" (`Int 42);
  Alcotest.(check bool) "has_variable" true (Executor.evaluate_condition memory (Nodes.Has_variable "key1"));
  Alcotest.(check bool) "missing variable" false (Executor.evaluate_condition memory (Nodes.Has_variable "missing"));
  Alcotest.(check bool) "not_has_variable" true (Executor.evaluate_condition memory (Nodes.Not_has_variable "missing"));
  Alcotest.(check bool) "not_has_variable false" false (Executor.evaluate_condition memory (Nodes.Not_has_variable "key1"));
  Alcotest.(check bool) "equals true" true (Executor.evaluate_condition memory (Nodes.Equals { key = "key1"; value = "value1" }));
  Alcotest.(check bool) "equals false" false (Executor.evaluate_condition memory (Nodes.Equals { key = "key1"; value = "wrong" }));
  Alcotest.(check bool) "not condition" true (Executor.evaluate_condition memory (Nodes.Not (Nodes.Has_variable "missing")));
  Alcotest.(check bool) "not condition false" false (Executor.evaluate_condition memory (Nodes.Not (Nodes.Has_variable "key1")))

let test_executor_llm_flow () =
  let responses = ref [] in
  let fake_chat ?temperature:_ ?model:_ _client ~messages =
    responses := messages;
    Lwt.return_ok "Stub result"
  in
  let client = Openai_client.create ~api_key:"test" () in
  let executor = Executor.create ~chat:fake_chat client in
  let memory = Memory.init "Execute action" in
  let plan =
    [
      Nodes.Action
        {
          id = "action";
          label = "Run";
          tool = Some "llm";
          prompt = "Provide output";
          save_as = Some "action_result";
        };
      Nodes.Finish { id = "finish"; summary = Some "Completed" };
    ]
  in
  let updated_memory, finished =
    run_lwt_result_or_fail (Executor.execute executor plan ~memory ~goal:"Execute action")
  in
  Alcotest.(check bool) "finished" true finished;
  Alcotest.(check int) "iterations" 1 (Memory.iterations memory);
  (match Memory.get_variable updated_memory "action_result" with
  | Some (`String v) -> Alcotest.(check string) "action result" "Stub result" v
  | _ -> Alcotest.fail "Expected action result");
  Alcotest.(check (option string)) "final answer" (Some "Completed") (Memory.get_answer updated_memory);
  Alcotest.(check int) "messages sent" 2 (List.length !responses)

(* Planner tests *)

let test_summary_excerpt () =
  let mem = Memory.init "Test goal with a very long description" in
  Memory.set_variable_string mem "key1" "value1";
  Memory.set_variable_string mem "key2" "value2";
  let summary = Tools.summary_excerpt mem in
  Alcotest.(check bool) "length" true (String.length summary <= Tools.max_summary_length)

let test_planner_strip_code_fence () =
  let with_fence = "```json\n{\"key\": \"value\"}\n```" in
  let stripped = Planner.strip_code_fence with_fence in
  Alcotest.(check string) "strip code fence" "{\"key\": \"value\"}" (String.trim stripped);
  let without_fence = "{\"key\": \"value\"}" in
  let unchanged = Planner.strip_code_fence without_fence in
  Alcotest.(check string) "no fence" without_fence (String.trim unchanged)

let test_planner_extract_json () =
  let valid_json = "{\"plan\": []}" in
  (match Planner.extract_json_candidate valid_json with
  | Ok _ -> ()
  | Error msg -> Alcotest.failf "Failed to extract valid json: %s" msg);
  let with_text = "Some text before {\"plan\": []} some text after" in
  (match Planner.extract_json_candidate with_text with
  | Ok _ -> ()
  | Error msg -> Alcotest.failf "Failed to extract embedded json: %s" msg);
  let invalid = "not json at all" in
  (match Planner.extract_json_candidate invalid with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "Expected extraction to fail")

let test_planner_plan_integration () =
  let captured_messages = ref [] in
  let fake_chat ?temperature:_ ?model:_ _client ~messages =
    captured_messages := messages;
    Lwt.return_ok "{\"plan\": [{\"type\": \"finish\", \"id\": \"finish\", \"summary\": \"Done\"}]}"
  in
  let client = Openai_client.create ~api_key:"test" () in
  let planner = Planner.create ~chat:fake_chat client in
  let memory = Memory.init "Plan goal" in
  Memory.set_variable_string memory "key" "value";
  let plan = run_lwt_result_or_fail (Planner.plan planner ~goal:"Plan goal" ~memory) in
  Alcotest.(check int) "plan length" 1 (List.length plan);
  (match List.hd plan with
  | Nodes.Finish finish -> Alcotest.(check (option string)) "summary" (Some "Done") finish.summary
  | _ -> Alcotest.fail "Expected finish node");
  Alcotest.(check int) "messages" 2 (List.length !captured_messages);
  match !captured_messages with
  | _system :: user :: _ ->
      Alcotest.(check string) "user role" "user" user.Openai_client.Message.role;
      Alcotest.(check bool) "goal included" true (string_contains ~needle:"Plan goal" user.content);
      Alcotest.(check bool) "memory snapshot included" true (string_contains ~needle:"key" user.content)
  | _ -> Alcotest.fail "Expected conversation with system and user messages"

let memory_tests =
  [
    Alcotest.test_case "init" `Quick test_memory_init;
    Alcotest.test_case "variables" `Quick test_memory_variables;
    Alcotest.test_case "completion" `Quick test_memory_completion;
    Alcotest.test_case "serialization roundtrip" `Quick test_memory_serialization_roundtrip;
    Alcotest.test_case "status serialization" `Quick test_memory_status_serialization;
    Alcotest.test_case "save/load file" `Quick test_memory_save_load_file;
    Alcotest.test_case "load nonexistent" `Quick test_memory_load_nonexistent;
  ]

let nodes_tests =
  [
    Alcotest.test_case "parse action" `Quick test_parse_action_node;
    Alcotest.test_case "parse branch" `Quick test_parse_branch_node;
  ]

let executor_tests =
  [
    Alcotest.test_case "conditions" `Quick test_executor_condition_evaluation;
    Alcotest.test_case "llm flow" `Quick test_executor_llm_flow;
  ]

let planner_tests =
  [
    Alcotest.test_case "summary excerpt" `Quick test_summary_excerpt;
    Alcotest.test_case "strip code fence" `Quick test_planner_strip_code_fence;
    Alcotest.test_case "extract json" `Quick test_planner_extract_json;
    Alcotest.test_case "plan integration" `Quick test_planner_plan_integration;
  ]

let () =
  Alcotest.run
    "agents"
    [ "Memory", memory_tests; "Nodes", nodes_tests; "Executor", executor_tests; "Planner", planner_tests ]