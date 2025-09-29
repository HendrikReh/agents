open Cmdliner

let strip_quotes s =
  let len = String.length s in
  if len >= 2 then
    match (s.[0], s.[len - 1]) with
    | ('"', '"') | ('\'', '\'') -> String.sub s 1 (len - 2)
    | _ -> s
  else
    s

let parse_env_line line =
  let trimmed = String.trim line in
  if trimmed = "" || trimmed.[0] = '#' then
    None
  else
    let trimmed =
      if String.length trimmed >= 7 && String.sub trimmed 0 7 = "export " then
        String.sub trimmed 7 (String.length trimmed - 7)
      else
        trimmed
    in
    match String.index_opt trimmed '=' with
    | None -> None
    | Some idx ->
        let key = String.sub trimmed 0 idx |> String.trim in
        let value =
          String.sub trimmed (idx + 1) (String.length trimmed - idx - 1)
          |> String.trim
          |> strip_quotes
        in
        if key = "" then None else Some (key, value)

let load_env path =
  if Sys.file_exists path then
    let ic = open_in path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr ic)
      (fun () ->
        try
          while true do
            let line = input_line ic in
            match parse_env_line line with
            | Some (key, value) ->
                if Sys.getenv_opt key = None then Unix.putenv key value
            | None -> ()
          done
        with End_of_file -> ())

let ensure_api_key () =
  match Sys.getenv_opt "OPENAI_API_KEY" with
  | Some key when String.trim key <> "" -> Ok key
  | _ -> Error "OPENAI_API_KEY is missing. Set it via environment or .env file."

let run_agent ~goal ~max_cycles ~model =
  load_env ".env";
  match ensure_api_key () with
  | Error _ as err -> err
  | Ok api_key ->
      let client = Agents.Openai_client.create ~api_key ?model () in
      let planner = Agents.Planner.create client in
      let executor = Agents.Executor.create client in
      let agent = Agents.Agent.create ~planner ~executor ~max_cycles () in
      match Lwt_main.run (Agents.Agent.run agent goal) with
      | Ok answer -> Ok answer
      | Error msg -> Error msg

let exec goal max_cycles model =
  match run_agent ~goal ~max_cycles ~model with
  | Ok answer ->
      Printf.printf "Final answer: %s\n" answer;
      `Ok ()
  | Error msg -> `Error (true, msg)

let goal_term =
  let doc = "Goal or task for the planner-style agent." in
  Arg.(value & opt string "Summarize the latest OCaml news" & info [ "g"; "goal" ] ~doc)

let max_cycles_term =
  let doc = "Maximum plan/execute cycles before giving up." in
  Arg.(value & opt int 4 & info [ "c"; "max-cycles" ] ~docv:"N" ~doc)

let model_term =
  let doc = "Override the default OpenAI model (defaults to gpt-5)." in
  Arg.(value & opt (some string) None & info [ "m"; "model" ] ~doc)

let cmd =
  let doc = "Planner-style LangGraph-inspired agent PoC in OCaml." in
  let info = Cmd.info "agents" ~doc in
  let term = Term.(ret (const exec $ goal_term $ max_cycles_term $ model_term)) in
  Cmd.v info term

let () = exit (Cmd.eval cmd)
