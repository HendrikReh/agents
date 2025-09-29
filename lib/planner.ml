let ( let* ) = Lwt_result.bind

let default_system_prompt =
  {|
You are an OCaml planning module that outputs structured JSON describing agent workflows.
Respond ONLY with valid JSON using this schema:
{
  "plan": [
    {
      "id": "unique_step_id",
      "type": "action" | "branch" | "loop" | "finish",
      "label": "human readable summary",
      "prompt": "instruction for executor (required for action)",
      "tool": "llm" (optional for action),
      "save_as": "memory_key" (optional for action),
      "condition": { ... } (required for branch/loop),
      "if_true": [ ... ] (for branch),
      "if_false": [ ... ]  (for branch),
      "body": [ ... ] (for loop),
      "max_iterations": 2 (optional for loop),
      "summary": "text" (for finish)
    }
  ]
}
Supported condition types:
- {"type": "always"}
- {"type": "has_variable", "key": "name"}
- {"type": "not_has_variable", "key": "name"}
- {"type": "equals", "key": "name", "value": "literal"}
- {"type": "not", "condition": { ... }}
Always provide one finish node to mark completion.
|}

let strip_code_fence text =
  let trimmed = String.trim text in
  if String.length trimmed >= 3 && String.sub trimmed 0 3 = "```" then
    let without_prefix =
      match String.index_opt trimmed '\n' with
      | None -> trimmed
      | Some idx -> String.sub trimmed (idx + 1) (String.length trimmed - idx - 1)
    in
    let remove_suffix s =
      let s = String.trim s in
      let len = String.length s in
      if len >= 3 && String.sub s (len - 3) 3 = "```" then
        String.sub s 0 (len - 3)
      else
        s
    in
    remove_suffix without_prefix |> String.trim
  else
    trimmed

let extract_json_candidate text =
  let trimmed = strip_code_fence text in
  let try_direct () =
    try Some (Yojson.Safe.from_string trimmed) with Yojson.Json_error _ -> None
  in
  match try_direct () with
  | Some json -> Ok json
  | None ->
      let len = String.length trimmed in
      let first_brace = ref None in
      let last_brace = ref None in
      for idx = 0 to len - 1 do
        match trimmed.[idx] with
        | '{' -> if !first_brace = None then first_brace := Some idx
        | '}' -> last_brace := Some idx
        | _ -> ()
      done;
      (match (!first_brace, !last_brace) with
      | Some start_idx, Some end_idx when end_idx > start_idx ->
          let candidate = String.sub trimmed start_idx (end_idx - start_idx + 1) in
          (try Ok (Yojson.Safe.from_string candidate) with Yojson.Json_error msg ->
             Error
               (Printf.sprintf
                  "Planner response did not contain valid JSON (parse error: %s).\nRaw: %s"
                  msg text))
      | _ ->
          Error
            (Printf.sprintf
               "Planner response did not include JSON object. Raw response: %s"
               text))

module type S = sig
  val plan : goal:string -> memory:Memory.t -> (Nodes.plan, string) result Lwt.t
end

type t = {
  client : Openai_client.t;
  system_prompt : string;
  temperature : float;
}

let create ?(system_prompt = default_system_prompt) ?(temperature = 0.1) client =
  { client; system_prompt; temperature }

let render_user_prompt ~goal ~memory =
  Printf.sprintf
    {|
Current goal: %s
Shared memory snapshot:
%s

Design a plan leveraging available tools. Prefer short, actionable steps.
Return only JSON following the schema.
|}
    goal
    (Tools.summary_excerpt memory)

let plan t ~goal ~memory =
  let messages =
    [
      Openai_client.Message.{ role = "system"; content = t.system_prompt };
      Openai_client.Message.{ role = "user"; content = render_user_prompt ~goal ~memory };
    ]
  in
  let* raw = Openai_client.chat ~temperature:t.temperature t.client ~messages in
  match extract_json_candidate raw with
  | Error msg -> Lwt_result.fail msg
  | Ok json -> (
      try Lwt_result.return (Nodes.plan_of_yojson json)
      with Nodes.Parse_error msg ->
        Lwt_result.fail
          (Printf.sprintf "Planner JSON schema error: %s\nRaw: %s" msg raw))
