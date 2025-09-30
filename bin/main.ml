open Cmdliner

let setup_logging level =
  Logs.set_level level;
  (* Force color output by setting up stderr formatter with style renderer *)
  let stderr_fmt = Format.err_formatter in
  Fmt.set_style_renderer stderr_fmt `Ansi_tty;

  let report src level ~over k msgf =
    let style =
      match level with
      | Logs.App -> `None
      | Logs.Error -> `Red
      | Logs.Warning -> `Yellow
      | Logs.Info -> `Blue
      | Logs.Debug -> `Cyan
    in
    let k _ = over (); k () in
    msgf @@ fun ?header ?tags:_ fmt ->
    let src_name = Option.value ~default:(Logs.Src.name src) header in
    Fmt.pf stderr_fmt "%a[%a] %a"
      Fmt.(styled style string)
      ""
      Fmt.(styled style string)
      src_name
      Fmt.(styled style string)
      "";
    Format.kfprintf k stderr_fmt (fmt ^^ "@.")
  in
  Logs.set_reporter { Logs.report }

let strip_quotes s =
  let len = String.length s in
  if len >= 2 then
    match (s.[0], s.[len - 1]) with
    | '"', '"' | '\'', '\'' -> String.sub s 1 (len - 2)
    | _ -> s
  else s

let parse_env_line line =
  let trimmed = String.trim line in
  if trimmed = "" || trimmed.[0] = '#' then None
  else
    let trimmed =
      if String.length trimmed >= 7 && String.sub trimmed 0 7 = "export " then
        String.sub trimmed 7 (String.length trimmed - 7)
      else trimmed
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
            | Some (key, value) -> if Sys.getenv_opt key = None then Unix.putenv key value
            | None -> ()
          done
        with End_of_file -> () )

let ensure_api_key () =
  match Sys.getenv_opt "OPENAI_API_KEY" with
  | Some key when String.trim key <> "" -> Ok key
  | _ -> Error "OPENAI_API_KEY is missing. Set it via environment or .env file."

module Log = Agents.Logging.Memory

let run_agent ~goal ~max_cycles ~model ~load_state ~save_state =
  load_env ".env";
  match ensure_api_key () with
  | Error _ as err -> err
  | Ok api_key -> (
    (* Load or initialize memory *)
    let memory_result =
      match load_state with
      | None ->
        Log.info (fun m -> m "Initializing fresh memory for goal: %s" goal);
        Ok (Agents.Memory.init goal)
      | Some path -> (
        Log.info (fun m -> m "Loading state from: %s" path);
        match Agents.Memory.load_from_file path with
        | Ok mem ->
          Log.info (fun m ->
              m "State loaded successfully (cycle %d)" (Agents.Memory.iterations mem) );
          Ok mem
        | Error e ->
          Log.err (fun m -> m "Failed to load state: %s" e);
          Error e )
    in
    match memory_result with
    | Error e -> Error e
    | Ok memory -> (
      let client = Agents.Openai_client.create ~api_key ?model () in
      let planner = Agents.Planner.create client in
      let executor = Agents.Executor.create client in
      let agent = Agents.Agent.create ~planner ~executor ~max_cycles () in
      match Lwt_main.run (Agents.Agent.run_with_memory agent memory) with
      | Ok (answer, final_memory) ->
        (* Save state if requested *)
        ( match save_state with
        | None -> ()
        | Some path -> (
          Log.info (fun m -> m "Saving state to: %s" path);
          match Agents.Memory.save_to_file final_memory path with
          | Ok () -> Log.info (fun m -> m "State saved successfully")
          | Error e -> Log.err (fun m -> m "Failed to save state: %s" e) ) );
        Ok answer
      | Error msg -> Error msg ) )

let exec goal max_cycles model log_level load_state save_state =
  setup_logging log_level;
  match run_agent ~goal ~max_cycles ~model ~load_state ~save_state with
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

let log_level_term =
  let doc = "Set log level: debug, info, warning, error, or app (default: info)." in
  let parse_level = function
    | "debug" -> Ok (Some Logs.Debug)
    | "info" -> Ok (Some Logs.Info)
    | "warning" -> Ok (Some Logs.Warning)
    | "error" -> Ok (Some Logs.Error)
    | "app" -> Ok (Some Logs.App)
    | "quiet" -> Ok None
    | s -> Error (`Msg ("Invalid log level: " ^ s))
  in
  let print_level fmt = function
    | Some Logs.Debug -> Format.fprintf fmt "debug"
    | Some Logs.Info -> Format.fprintf fmt "info"
    | Some Logs.Warning -> Format.fprintf fmt "warning"
    | Some Logs.Error -> Format.fprintf fmt "error"
    | Some Logs.App -> Format.fprintf fmt "app"
    | None -> Format.fprintf fmt "quiet"
  in
  let converter = Arg.conv (parse_level, print_level) in
  Arg.(value & opt converter (Some Logs.Info) & info [ "l"; "log-level" ] ~doc)

let load_state_term =
  let doc = "Load agent state from a JSON file to resume execution." in
  Arg.(value & opt (some string) None & info [ "load-state" ] ~docv:"PATH" ~doc)

let save_state_term =
  let doc = "Save final agent state to a JSON file." in
  Arg.(value & opt (some string) None & info [ "save-state" ] ~docv:"PATH" ~doc)

let cmd =
  let doc = "Planner-style LangGraph-inspired agent PoC in OCaml." in
  let info = Cmd.info "agents" ~doc in
  let term =
    Term.(
      ret
        ( const exec
        $ goal_term
        $ max_cycles_term
        $ model_term
        $ log_level_term
        $ load_state_term
        $ save_state_term ) )
  in
  Cmd.v info term

let () = exit (Cmd.eval cmd)
