let ( let* ) = Lwt_result.bind

module Log = Logging.Executor

let default_loop_iterations = 3

let tool_or_default action = Option.value ~default:"llm" action.Nodes.tool

let rec evaluate_condition memory = function
  | Nodes.Always -> true
  | Nodes.Has_variable key -> Option.is_some (Memory.get_variable memory key)
  | Nodes.Not_has_variable key -> Option.is_none (Memory.get_variable memory key)
  | Nodes.Equals { key; value } -> (
    match Memory.get_variable memory key with
    | Some (`String stored) -> String.equal stored value
    | Some json -> String.equal (Yojson.Safe.to_string json) value
    | None -> false
  )
  | Nodes.Not condition -> not (evaluate_condition memory condition)

let normalise_save_key action =
  match action.Nodes.save_as with
  | Some key when String.trim key <> "" -> String.trim key
  | _ -> action.Nodes.id

type chat_fn =
  ?temperature:float ->
  ?model:string option ->
  Openai_client.t ->
  messages:Openai_client.Message.t list ->
  (string, string) result Lwt.t

let default_chat : chat_fn = Openai_client.chat

type t = {
  client : Openai_client.t;
  default_loop_iterations : int;
  chat : chat_fn;
}

let create ?(default_loop_iterations = default_loop_iterations) ?chat client =
  let chat = Option.value ~default:default_chat chat in
  Log.info (fun m ->
      m "Creating executor with default_loop_iterations=%d" default_loop_iterations );
  { client; default_loop_iterations; chat }

let render_action_prompt ~goal ~memory (action : Nodes.action) =
  Printf.sprintf
    {|
You are executing action '%s' (%s).
Goal: %s
Current memory summary:
%s

Follow the instruction below and reply with the direct result (no commentary):
%s
|}
    action.Nodes.id action.Nodes.label goal
    (Tools.summary_excerpt memory)
    action.Nodes.prompt

let run_llm_action t ~goal ~memory (action : Nodes.action) =
  Log.info (fun m -> m "Executing LLM action: %s (%s)" action.Nodes.id action.Nodes.label);
  let prompt = render_action_prompt ~goal ~memory action in
  let messages =
    [
      Openai_client.Message.
        {
          role = "system";
          content =
            "You are a precise tool executor. Always provide concise outputs "
            ^ "without commentary.";
        };
      Openai_client.Message.{ role = "user"; content = prompt };
    ]
  in
  let* response = t.chat t.client ~messages ~temperature:0.2 in
  let key = normalise_save_key action in
  Log.debug (fun m -> m "Saving action result to key: %s" key);
  Memory.set_variable memory key (`String response);
  Memory.set_last_result memory response;
  Lwt_result.return (memory, false)

let run_action t ~goal ~memory action =
  match String.lowercase_ascii (tool_or_default action) with
  | "llm" -> run_llm_action t ~goal ~memory action
  | other ->
    Log.err (fun m -> m "Unsupported tool '%s' for action %s" other action.Nodes.id);
    Lwt_result.fail
      (Printf.sprintf "Unsupported tool '%s' for action %s" other action.Nodes.id)

let rec run_nodes t ~goal ~memory nodes =
  match nodes with
  | [] -> Lwt_result.return (memory, false)
  | node :: rest ->
    let* memory_after, finished_node = run_node t ~goal ~memory node in
    if finished_node then Lwt_result.return (memory_after, true)
    else run_nodes t ~goal ~memory:memory_after rest

and run_node t ~goal ~memory = function
  | Nodes.Action action -> run_action t ~goal ~memory action
  | Nodes.Branch branch -> run_branch t ~goal ~memory branch
  | Nodes.Loop loop -> run_loop t ~goal ~memory loop
  | Nodes.Finish finish -> run_finish ~memory finish

and run_branch t ~goal ~memory branch =
  let condition_result = evaluate_condition memory branch.Nodes.condition in
  Log.debug (fun m -> m "Branch condition evaluated to: %b" condition_result);
  let path = if condition_result then branch.Nodes.if_true else branch.Nodes.if_false in
  run_nodes t ~goal ~memory path

and run_loop t ~goal ~memory loop =
  let max_iterations =
    match loop.Nodes.max_iterations with
    | Some value when value > 0 -> value
    | _ -> t.default_loop_iterations
  in
  Log.debug (fun m -> m "Starting loop with max_iterations=%d" max_iterations);
  let rec apply iteration memory_acc =
    if not (evaluate_condition memory_acc loop.Nodes.condition) then (
      Log.debug (fun m -> m "Loop condition false at iteration %d" iteration);
      Lwt_result.return (memory_acc, false)
    )
    else if iteration >= max_iterations then (
      Log.debug (fun m -> m "Loop reached max_iterations at %d" iteration);
      Lwt_result.return (memory_acc, false)
    )
    else (
      Log.debug (fun m -> m "Loop iteration %d/%d" (iteration + 1) max_iterations);
      let* memory_body, finished = run_nodes t ~goal ~memory:memory_acc loop.Nodes.body in
      if finished then Lwt_result.return (memory_body, true)
      else apply (succ iteration) memory_body
    )
  in
  apply 0 memory

and run_finish ~memory finish =
  Log.info (fun m -> m "Reached finish node");
  ( match finish.Nodes.summary with
  | Some text when String.trim text <> "" ->
    Log.debug (fun m -> m "Marking completed with summary");
    Memory.mark_completed memory text
  | _ -> (
    match Memory.last_result memory with
    | Some result when String.trim result <> "" ->
      Log.debug (fun m -> m "Marking completed with last result");
      Memory.mark_completed memory result
    | _ ->
      Log.debug (fun m -> m "Marking completed with no result");
      Memory.mark_completed memory "<no result>"
  ) );
  Lwt_result.return (memory, true)

let execute t plan ~memory ~goal =
  Log.info (fun m -> m "Executing plan with %d nodes" (List.length plan));
  Memory.bump_iteration memory;
  run_nodes t ~goal ~memory plan
