let ( let* ) = Lwt_result.bind
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
      | None -> false)
  | Nodes.Not condition -> not (evaluate_condition memory condition)

let normalise_save_key action =
  match action.Nodes.save_as with
  | Some key when String.trim key <> "" -> String.trim key
  | _ -> action.Nodes.id

type t = {
  client : Openai_client.t;
  default_loop_iterations : int;
}

let create ?(default_loop_iterations = default_loop_iterations) client =
  { client; default_loop_iterations }

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
    action.Nodes.id
    action.Nodes.label
    goal
    (Tools.summary_excerpt memory)
    action.Nodes.prompt

let run_llm_action t ~goal ~memory action =
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
  let* response = Openai_client.chat t.client ~messages ~temperature:0.2 in
  let key = normalise_save_key action in
  Memory.set_variable memory key (`String response);
  Memory.set_last_result memory response;
  Lwt_result.return (memory, false)

let run_action t ~goal ~memory action =
  match String.lowercase_ascii (tool_or_default action) with
  | "llm" -> run_llm_action t ~goal ~memory action
  | other ->
      Lwt_result.fail (Printf.sprintf "Unsupported tool '%s' for action %s" other action.Nodes.id)

let rec run_nodes t ~goal ~memory nodes =
  match nodes with
  | [] -> Lwt_result.return (memory, false)
  | node :: rest ->
      let* memory_after, finished_node = run_node t ~goal ~memory node in
      if finished_node then
        Lwt_result.return (memory_after, true)
      else
        run_nodes t ~goal ~memory:memory_after rest

and run_node t ~goal ~memory = function
  | Nodes.Action action -> run_action t ~goal ~memory action
  | Nodes.Branch branch -> run_branch t ~goal ~memory branch
  | Nodes.Loop loop -> run_loop t ~goal ~memory loop
  | Nodes.Finish finish -> run_finish ~memory finish

and run_branch t ~goal ~memory branch =
  let path = if evaluate_condition memory branch.Nodes.condition then branch.Nodes.if_true else branch.Nodes.if_false in
  run_nodes t ~goal ~memory path

and run_loop t ~goal ~memory loop =
  let max_iterations =
    match loop.Nodes.max_iterations with
    | Some value when value > 0 -> value
    | _ -> t.default_loop_iterations
  in
  let rec apply iteration memory_acc =
    if not (evaluate_condition memory_acc loop.Nodes.condition) then
      Lwt_result.return (memory_acc, false)
    else if iteration >= max_iterations then
      Lwt_result.return (memory_acc, false)
    else
      let* memory_body, finished =
        run_nodes t ~goal ~memory:memory_acc loop.Nodes.body
      in
      if finished then
        Lwt_result.return (memory_body, true)
      else
        apply (succ iteration) memory_body
  in
  apply 0 memory

and run_finish ~memory finish =
  (match finish.Nodes.summary with
  | Some text when String.trim text <> "" -> Memory.mark_completed memory text
  | _ -> (
      match Memory.last_result memory with
      | Some result when String.trim result <> "" -> Memory.mark_completed memory result
      | _ -> Memory.mark_completed memory "<no result>"));
  Lwt_result.return (memory, true)

let execute t plan ~memory ~goal =
  Memory.bump_iteration memory;
  run_nodes t ~goal ~memory plan
