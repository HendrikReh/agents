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
  match Lwt_main.run promise with Ok value -> value | Error msg -> Alcotest.fail msg

let run_lwt_result_expect_error promise =
  match Lwt_main.run promise with
  | Ok _ -> Alcotest.fail "Expected operation to fail"
  | Error msg -> msg

let string_contains ~needle haystack =
  let needle_len = String.length needle in
  let haystack_len = String.length haystack in
  let rec scan idx =
    if idx + needle_len > haystack_len then false
    else if String.sub haystack idx needle_len = needle then true
    else scan (idx + 1)
  in
  scan 0

let write_file path content =
  let oc = open_out path in
  Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () -> output_string oc content)

let check (type a) (testable : a Alcotest.testable) msg expected actual =
  let module T = (val testable : Alcotest.TESTABLE with type t = a) in
  if T.equal expected actual then ()
  else
    let message =
      Format.asprintf "%s\nexpected: %a\nactual: %a" msg T.pp expected T.pp actual
    in
    Alcotest.fail message

(* Memory module tests *)

let test_memory_init () =
  let mem = Memory.init test_goal in
  check Alcotest.string "goal" test_goal (Memory.goal mem);
  check status_testable "status" Memory.In_progress (Memory.status mem);
  check Alcotest.int "iterations" 0 (Memory.iterations mem);
  check (Alcotest.option Alcotest.string) "last_result" None (Memory.last_result mem)

let test_memory_variables () =
  let mem = Memory.init test_goal in
  Memory.set_variable_string mem "test_key" "test_value";
  match Memory.get_variable mem "test_key" with
  | Some (`String value) -> check Alcotest.string "variable" "test_value" value
  | _ -> Alcotest.fail "Expected string variable"

let test_memory_completion () =
  let mem = Memory.init test_goal in
  let answer = "The answer is 4" in
  Memory.mark_completed mem answer;
  ( match Memory.status mem with
  | Memory.Completed stored -> check Alcotest.string "completed answer" answer stored
  | _ -> Alcotest.fail "Status should be completed" );
  check
    (Alcotest.option Alcotest.string)
    "get_answer" (Some answer) (Memory.get_answer mem)

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
  | Ok restored -> (
    check Alcotest.string "goal" "Test goal for serialization" (Memory.goal restored);
    check Alcotest.int "iterations" 2 (Memory.iterations restored);
    check
      (Alcotest.option Alcotest.string)
      "last_result" (Some "Last result text") (Memory.last_result restored);
    ( match Memory.get_variable restored "key1" with
    | Some (`String v) -> check Alcotest.string "key1" "value1" v
    | _ -> Alcotest.fail "Expected string for key1" );
    ( match Memory.get_variable restored "key2" with
    | Some (`Int v) -> check Alcotest.int "key2" 42 v
    | _ -> Alcotest.fail "Expected int for key2" );
    match Memory.get_variable restored "key3" with
    | Some (`List values) -> check Alcotest.int "key3 length" 2 (List.length values)
    | _ -> Alcotest.fail "Expected list for key3" )

let test_memory_status_serialization () =
  let mem = Memory.init "Test status" in
  let json_in_progress = Memory.to_yojson mem in
  ( match Memory.of_yojson json_in_progress with
  | Ok restored ->
    check status_testable "in_progress" Memory.In_progress (Memory.status restored)
  | Error _ -> Alcotest.fail "Deserialization should succeed" );
  Memory.mark_completed mem "Test answer";
  let json_completed = Memory.to_yojson mem in
  ( match Memory.of_yojson json_completed with
  | Ok restored -> (
    match Memory.status restored with
    | Memory.Completed answer -> check Alcotest.string "completed" "Test answer" answer
    | _ -> Alcotest.fail "Status should be completed" )
  | Error _ -> Alcotest.fail "Deserialization should succeed" );
  let mem_failed = Memory.init "Test failed" in
  Memory.mark_failed mem_failed ~reason:"Test failure";
  let json_failed = Memory.to_yojson mem_failed in
  match Memory.of_yojson json_failed with
  | Ok restored -> (
    match Memory.status restored with
    | Memory.Failed reason -> check Alcotest.string "failed" "Test failure" reason
    | _ -> Alcotest.fail "Status should be failed" )
  | Error _ -> Alcotest.fail "Deserialization should succeed"

let test_memory_save_load_file () =
  let temp_file = Filename.temp_file "agent_test" ".json" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists temp_file then Sys.remove temp_file)
    (fun () ->
      let mem = Memory.init "File persistence test" in
      Memory.set_variable_string mem "saved_var" "saved_value";
      Memory.bump_iteration mem;
      ( match Memory.save_to_file mem temp_file with
      | Ok () -> ()
      | Error msg -> Alcotest.failf "Save failed: %s" msg );
      match Memory.load_from_file temp_file with
      | Error msg -> Alcotest.failf "Load failed: %s" msg
      | Ok restored -> (
        check Alcotest.string "goal" "File persistence test" (Memory.goal restored);
        check Alcotest.int "iterations" 1 (Memory.iterations restored);
        match Memory.get_variable restored "saved_var" with
        | Some (`String v) -> check Alcotest.string "saved_var" "saved_value" v
        | _ -> Alcotest.fail "Expected saved_var" ) )

let test_memory_load_nonexistent () =
  match Memory.load_from_file "/nonexistent/path/to/file.json" with
  | Error msg ->
    check Alcotest.bool "message" true
      (String.starts_with ~prefix:"State file not found" msg)
  | Ok _ -> Alcotest.fail "Expected load to fail"

let test_memory_load_corrupted_json () =
  let temp_file = Filename.temp_file "agent_test" ".json" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists temp_file then Sys.remove temp_file)
    (fun () ->
      write_file temp_file "not json";
      match Memory.load_from_file temp_file with
      | Error msg ->
        check Alcotest.bool "corrupted json message" true
          (string_contains ~needle:"Failed to parse state file" msg)
      | Ok _ -> Alcotest.fail "Expected corrupted load to fail" )

let test_memory_load_bad_version () =
  let temp_file = Filename.temp_file "agent_test" ".json" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists temp_file then Sys.remove temp_file)
    (fun () ->
      write_file temp_file
        "{\"version\": 2, \"goal\": \"Goal\", \"status\": {\"type\": \"in_progress\"}, \
         \"last_result\": null, \"iterations\": 0, \"variables\": []}";
      match Memory.load_from_file temp_file with
      | Error msg ->
        check Alcotest.bool "bad version message" true
          (string_contains ~needle:"Unsupported schema version" msg)
      | Ok _ -> Alcotest.fail "Expected unsupported version to fail" )

let test_memory_load_bad_status () =
  let temp_file = Filename.temp_file "agent_test" ".json" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists temp_file then Sys.remove temp_file)
    (fun () ->
      write_file temp_file
        "{\"version\": 1, \"goal\": \"Goal\", \"status\": {\"type\": \"unknown\"}, \
         \"last_result\": null, \"iterations\": 0, \"variables\": []}";
      match Memory.load_from_file temp_file with
      | Error msg ->
        check Alcotest.bool "bad status message" true
          (string_contains ~needle:"Unknown status type" msg)
      | Ok _ -> Alcotest.fail "Expected bad status to fail" )

let test_memory_load_bad_iterations () =
  let temp_file = Filename.temp_file "agent_test" ".json" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists temp_file then Sys.remove temp_file)
    (fun () ->
      write_file temp_file
        "{\"version\": 1, \"goal\": \"Goal\", \"status\": {\"type\": \"in_progress\"}, \
         \"last_result\": null, \"iterations\": \"oops\", \"variables\": []}";
      match Memory.load_from_file temp_file with
      | Error msg ->
        check Alcotest.bool "bad iterations message" true
          (string_contains ~needle:"Failed to parse memory" msg)
      | Ok _ -> Alcotest.fail "Expected iterations type error" )

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
    check Alcotest.string "id" "test_action" action.Nodes.id;
    check Alcotest.string "label" "Test Action" action.Nodes.label;
    check Alcotest.string "prompt" "Do something" action.Nodes.prompt;
    check (Alcotest.option Alcotest.string) "tool" (Some "llm") action.Nodes.tool
  | _ -> Alcotest.fail "Expected action node"

let test_parse_branch_node () =
  let json =
    `Assoc
      [
        ("type", `String "branch");
        ("id", `String "test_branch");
        ( "condition",
          `Assoc [ ("type", `String "has_variable"); ("key", `String "result") ] );
        ("if_true", `List []);
        ("if_false", `List []);
      ]
  in
  match Nodes.node_of_yojson json with
  | Nodes.Branch branch -> (
    check Alcotest.string "branch id" "test_branch" branch.Nodes.id;
    match branch.Nodes.condition with
    | Nodes.Has_variable key -> check Alcotest.string "branch key" "result" key
    | _ -> Alcotest.fail "Expected has_variable condition" )
  | _ -> Alcotest.fail "Expected branch node"

(* Nodes / executor tests *)

let test_executor_condition_evaluation () =
  let memory = Memory.init "Test conditions" in
  Memory.set_variable_string memory "key1" "value1";
  Memory.set_variable memory "key2" (`Int 42);
  check Alcotest.bool "has_variable" true
    (Executor.evaluate_condition memory (Nodes.Has_variable "key1"));
  check Alcotest.bool "missing variable" false
    (Executor.evaluate_condition memory (Nodes.Has_variable "missing"));
  check Alcotest.bool "not_has_variable" true
    (Executor.evaluate_condition memory (Nodes.Not_has_variable "missing"));
  check Alcotest.bool "not_has_variable false" false
    (Executor.evaluate_condition memory (Nodes.Not_has_variable "key1"));
  check Alcotest.bool "equals true" true
    (Executor.evaluate_condition memory (Nodes.Equals { key = "key1"; value = "value1" }));
  check Alcotest.bool "equals false" false
    (Executor.evaluate_condition memory (Nodes.Equals { key = "key1"; value = "wrong" }));
  check Alcotest.bool "not condition" true
    (Executor.evaluate_condition memory (Nodes.Not (Nodes.Has_variable "missing")));
  check Alcotest.bool "not condition false" false
    (Executor.evaluate_condition memory (Nodes.Not (Nodes.Has_variable "key1")))

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
  check Alcotest.bool "finished" true finished;
  check Alcotest.int "iterations" 1 (Memory.iterations memory);
  ( match Memory.get_variable updated_memory "action_result" with
  | Some (`String v) -> check Alcotest.string "action result" "Stub result" v
  | _ -> Alcotest.fail "Expected action result" );
  check
    (Alcotest.option Alcotest.string)
    "final answer" (Some "Completed")
    (Memory.get_answer updated_memory);
  check Alcotest.int "messages sent" 2 (List.length !responses)

let test_executor_loop_max_iterations () =
  let call_count = ref 0 in
  let fake_chat ?temperature:_ ?model:_ _client ~messages:_ =
    incr call_count;
    Lwt.return_ok (Printf.sprintf "iteration %d" !call_count)
  in
  let client = Openai_client.create ~api_key:"test" () in
  let executor = Executor.create ~chat:fake_chat client in
  let memory = Memory.init "Loop goal" in
  let loop_body =
    Nodes.Action
      {
        id = "loop_action";
        label = "Loop action";
        tool = None;
        prompt = "Perform loop step";
        save_as = Some "loop_result";
      }
  in
  let plan =
    [
      Nodes.Loop
        {
          id = "loop";
          condition = Nodes.Always;
          body = [ loop_body ];
          max_iterations = Some 2;
        };
      Nodes.Finish { id = "finish"; summary = Some "Loop done" };
    ]
  in
  let updated_memory, finished =
    run_lwt_result_or_fail (Executor.execute executor plan ~memory ~goal:"Loop goal")
  in
  check Alcotest.bool "finished" true finished;
  check Alcotest.int "loop iterations" 2 !call_count;
  ( match Memory.get_variable updated_memory "loop_result" with
  | Some (`String v) -> check Alcotest.string "final loop result" "iteration 2" v
  | _ -> Alcotest.fail "Expected loop_result variable" );
  check
    (Alcotest.option Alcotest.string)
    "final answer" (Some "Loop done")
    (Memory.get_answer updated_memory)

let test_executor_loop_condition_short_circuit () =
  let call_count = ref 0 in
  let fake_chat ?temperature:_ ?model:_ _client ~messages:_ =
    incr call_count;
    Lwt.return_ok "should not run"
  in
  let client = Openai_client.create ~api_key:"test" () in
  let executor = Executor.create ~chat:fake_chat client in
  let memory = Memory.init "Loop skips" in
  let loop =
    Nodes.Loop
      {
        id = "loop";
        condition = Nodes.Has_variable "ready";
        body =
          [
            Nodes.Action
              {
                id = "loop_action";
                label = "Loop action";
                tool = Some "llm";
                prompt = "Do work";
                save_as = Some "loop_result";
              };
          ];
        max_iterations = Some 3;
      }
  in
  let plan = [ loop; Nodes.Finish { id = "finish"; summary = Some "No iterations" } ] in
  let updated_memory, finished =
    run_lwt_result_or_fail (Executor.execute executor plan ~memory ~goal:"Loop skips")
  in
  check Alcotest.bool "finished" true finished;
  check Alcotest.int "loop iterations" 0 !call_count;
  check Alcotest.bool "loop result missing" true
    (Option.is_none (Memory.get_variable updated_memory "loop_result"));
  check
    (Alcotest.option Alcotest.string)
    "final answer" (Some "No iterations")
    (Memory.get_answer updated_memory)

let test_executor_unsupported_tool () =
  let fake_chat ?temperature:_ ?model:_ _client ~messages:_ =
    Alcotest.fail "Chat should not be invoked for unsupported tool"
  in
  let client = Openai_client.create ~api_key:"test" () in
  let executor = Executor.create ~chat:fake_chat client in
  let memory = Memory.init "Unsupported tool" in
  let plan =
    [
      Nodes.Action
        {
          id = "unsupported";
          label = "Unsupported";
          tool = Some "email";
          prompt = "Do something";
          save_as = None;
        };
    ]
  in
  let error =
    run_lwt_result_expect_error
      (Executor.execute executor plan ~memory ~goal:"Unsupported tool")
  in
  check Alcotest.bool "unsupported tool message" true
    (string_contains ~needle:"Unsupported tool" error)

(* Planner tests *)

let test_summary_excerpt () =
  let mem = Memory.init "Test goal with a very long description" in
  Memory.set_variable_string mem "key1" "value1";
  Memory.set_variable_string mem "key2" "value2";
  let summary = Tools.summary_excerpt mem in
  check Alcotest.bool "length" true (String.length summary <= Tools.max_summary_length)

let test_planner_strip_code_fence () =
  let with_fence = "```json\n{\"key\": \"value\"}\n```" in
  let stripped = Planner.strip_code_fence with_fence in
  check Alcotest.string "strip code fence" "{\"key\": \"value\"}" (String.trim stripped);
  let without_fence = "{\"key\": \"value\"}" in
  let unchanged = Planner.strip_code_fence without_fence in
  check Alcotest.string "no fence" without_fence (String.trim unchanged)

let test_planner_extract_json () =
  let valid_json = "{\"plan\": []}" in
  ( match Planner.extract_json_candidate valid_json with
  | Ok _ -> ()
  | Error msg -> Alcotest.failf "Failed to extract valid json: %s" msg );
  let with_text = "Some text before {\"plan\": []} some text after" in
  ( match Planner.extract_json_candidate with_text with
  | Ok _ -> ()
  | Error msg -> Alcotest.failf "Failed to extract embedded json: %s" msg );
  let invalid = "not json at all" in
  match Planner.extract_json_candidate invalid with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "Expected extraction to fail"

let test_planner_invalid_json_response () =
  let fake_chat ?temperature:_ ?model:_ _client ~messages:_ =
    Lwt.return_ok "no json here"
  in
  let client = Openai_client.create ~api_key:"test" () in
  let planner = Planner.create ~chat:fake_chat client in
  let memory = Memory.init "Invalid planner" in
  let error =
    run_lwt_result_expect_error (Planner.plan planner ~goal:"Invalid" ~memory)
  in
  check Alcotest.bool "missing json error" true
    (string_contains ~needle:"did not include JSON object" error)

let test_planner_schema_error () =
  let fake_chat ?temperature:_ ?model:_ _client ~messages:_ =
    Lwt.return_ok "{\"plan\": [{\"id\": \"step1\", \"type\": \"unknown\"}]}"
  in
  let client = Openai_client.create ~api_key:"test" () in
  let planner = Planner.create ~chat:fake_chat client in
  let memory = Memory.init "Schema error" in
  let error = run_lwt_result_expect_error (Planner.plan planner ~goal:"Schema" ~memory) in
  check Alcotest.bool "schema error reported" true
    (string_contains ~needle:"Planner JSON schema error" error);
  check Alcotest.bool "mentions unknown" true (string_contains ~needle:"unknown" error)

let test_planner_missing_plan_field () =
  let fake_chat ?temperature:_ ?model:_ _client ~messages:_ =
    Lwt.return_ok "{\"steps\": []}"
  in
  let client = Openai_client.create ~api_key:"test" () in
  let planner = Planner.create ~chat:fake_chat client in
  let memory = Memory.init "Missing plan" in
  let error =
    run_lwt_result_expect_error (Planner.plan planner ~goal:"Missing" ~memory)
  in
  check Alcotest.bool "missing plan error" true
    (string_contains ~needle:"Plan JSON must contain 'plan' or 'nodes'" error)

let test_planner_plan_integration () =
  let captured_messages = ref [] in
  let fake_chat ?temperature:_ ?model:_ _client ~messages =
    captured_messages := messages;
    Lwt.return_ok
      "{\"plan\": [{\"type\": \"finish\", \"id\": \"finish\", \"summary\": \"Done\"}]}"
  in
  let client = Openai_client.create ~api_key:"test" () in
  let planner = Planner.create ~chat:fake_chat client in
  let memory = Memory.init "Plan goal" in
  Memory.set_variable_string memory "key" "value";
  let plan = run_lwt_result_or_fail (Planner.plan planner ~goal:"Plan goal" ~memory) in
  check Alcotest.int "plan length" 1 (List.length plan);
  ( match List.hd plan with
  | Nodes.Finish finish ->
    check (Alcotest.option Alcotest.string) "summary" (Some "Done") finish.summary
  | _ -> Alcotest.fail "Expected finish node" );
  check Alcotest.int "messages" 2 (List.length !captured_messages);
  match !captured_messages with
  | _system :: user :: _ ->
    check Alcotest.string "user role" "user" user.Openai_client.Message.role;
    check Alcotest.bool "goal included" true
      (string_contains ~needle:"Plan goal" user.content);
    check Alcotest.bool "memory snapshot included" true
      (string_contains ~needle:"key" user.content)
  | _ -> Alcotest.fail "Expected conversation with system and user messages"

let quick_case name fn = (name, `Quick, fn)

let raw_suites =
  [
    ( "Memory",
      [
        quick_case "init" test_memory_init;
        quick_case "variables" test_memory_variables;
        quick_case "completion" test_memory_completion;
        quick_case "serialization roundtrip" test_memory_serialization_roundtrip;
        quick_case "status serialization" test_memory_status_serialization;
        quick_case "save/load file" test_memory_save_load_file;
        quick_case "load nonexistent" test_memory_load_nonexistent;
        quick_case "load corrupted json" test_memory_load_corrupted_json;
        quick_case "load bad version" test_memory_load_bad_version;
        quick_case "load bad status" test_memory_load_bad_status;
        quick_case "load bad iterations" test_memory_load_bad_iterations;
      ] );
    ( "Nodes",
      [
        quick_case "parse action" test_parse_action_node;
        quick_case "parse branch" test_parse_branch_node;
      ] );
    ( "Executor",
      [
        quick_case "conditions" test_executor_condition_evaluation;
        quick_case "llm flow" test_executor_llm_flow;
        quick_case "loop respects max iterations" test_executor_loop_max_iterations;
        quick_case "loop short circuit" test_executor_loop_condition_short_circuit;
        quick_case "unsupported tool" test_executor_unsupported_tool;
      ] );
    ( "Planner",
      [
        quick_case "summary excerpt" test_summary_excerpt;
        quick_case "strip code fence" test_planner_strip_code_fence;
        quick_case "extract json" test_planner_extract_json;
        quick_case "invalid json response" test_planner_invalid_json_response;
        quick_case "schema error" test_planner_schema_error;
        quick_case "missing plan field" test_planner_missing_plan_field;
        quick_case "plan integration" test_planner_plan_integration;
      ] );
  ]

let () = Alcotest.run "agents" raw_suites
