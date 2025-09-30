(* Agent memory captures goal, state variables, execution status, and tracking info. *)

type status =
  | In_progress
  | Completed of string
  | Failed of string

let status_to_string = function
  | In_progress -> "in_progress"
  | Completed _ -> "completed"
  | Failed _ -> "failed"

type t = {
  goal : string;
  variables : (string, Yojson.Safe.t) Hashtbl.t;
  mutable status : status;
  mutable last_result : string option;
  mutable iterations : int;
}

let init goal =
  {
    goal;
    variables = Hashtbl.create 32;
    status = In_progress;
    last_result = None;
    iterations = 0;
  }

let bump_iteration mem = mem.iterations <- mem.iterations + 1

let iterations mem = mem.iterations

let goal mem = mem.goal

let status mem = mem.status

let set_status mem status = mem.status <- status

let get_variable mem key = Hashtbl.find_opt mem.variables key

let set_variable mem key value = Hashtbl.replace mem.variables key value

let set_variable_string mem key value = set_variable mem key (`String value)

let last_result mem = mem.last_result

let set_last_result mem value = mem.last_result <- Some value

let data_snapshot mem =
  Hashtbl.fold (fun key value acc -> (key, value) :: acc) mem.variables []

let summary mem =
  let items =
    data_snapshot mem
    |> List.map (fun (k, v) ->
           let value_string =
             match v with `String s -> s | _ -> Yojson.Safe.to_string v
           in
           Printf.sprintf "%s: %s" k value_string )
  in
  let items = if items = [] then "<empty>" else String.concat "; " items in
  Printf.sprintf "Goal: %s\nStatus: %s\nLast result: %s\nVariables: %s" mem.goal
    (status_to_string mem.status)
    (match mem.last_result with None -> "<none>" | Some v -> v)
    items

let mark_completed mem answer =
  set_status mem (Completed answer);
  set_last_result mem answer;
  set_variable_string mem "final_answer" answer

let mark_failed mem ~reason =
  set_status mem (Failed reason);
  set_last_result mem reason

let ensure_default mem key value =
  match get_variable mem key with None -> set_variable mem key value | Some _ -> ()

let get_answer mem =
  match mem.status with
  | Completed answer -> Some answer
  | _ -> ( match get_variable mem "final_answer" with Some (`String s) -> Some s | _ -> None )

(* Serialization for state persistence *)

let status_to_yojson = function
  | In_progress -> `Assoc [ ("type", `String "in_progress") ]
  | Completed answer ->
    `Assoc [ ("type", `String "completed"); ("answer", `String answer) ]
  | Failed reason -> `Assoc [ ("type", `String "failed"); ("reason", `String reason) ]

let status_of_yojson json =
  try
    let open Yojson.Safe.Util in
    let typ = json |> member "type" |> to_string in
    match typ with
    | "in_progress" -> Ok In_progress
    | "completed" ->
      let answer = json |> member "answer" |> to_string in
      Ok (Completed answer)
    | "failed" ->
      let reason = json |> member "reason" |> to_string in
      Ok (Failed reason)
    | _ -> Error (Printf.sprintf "Unknown status type: %s" typ)
  with Yojson.Safe.Util.Type_error (msg, _) ->
    Error (Printf.sprintf "Failed to parse status: %s" msg)

let to_yojson mem =
  let variables_list =
    data_snapshot mem
    |> List.map (fun (k, v) -> `Assoc [ ("key", `String k); ("value", v) ])
  in
  `Assoc
    [
      ("version", `Int 1);
      ("goal", `String mem.goal);
      ("status", status_to_yojson mem.status);
      ("last_result", match mem.last_result with None -> `Null | Some r -> `String r);
      ("iterations", `Int mem.iterations);
      ("variables", `List variables_list);
    ]

let of_yojson json =
  try
    let open Yojson.Safe.Util in
    let version = json |> member "version" |> to_int in
    if version <> 1 then Error (Printf.sprintf "Unsupported schema version: %d" version)
    else
      let goal = json |> member "goal" |> to_string in
      let status_json = json |> member "status" in
      let last_result =
        match json |> member "last_result" with
        | `Null -> None
        | `String s -> Some s
        | _ -> None
      in
      let iterations = json |> member "iterations" |> to_int in
      let variables_json = json |> member "variables" |> to_list in
      match status_of_yojson status_json with
      | Error e -> Error e
      | Ok status ->
        let variables = Hashtbl.create 32 in
        List.iter
          (fun var_obj ->
            let key = var_obj |> member "key" |> to_string in
            let value = var_obj |> member "value" in
            Hashtbl.add variables key value )
          variables_json;
        Ok { goal; variables; status; last_result; iterations }
  with
  | Yojson.Safe.Util.Type_error (msg, _) -> Error (Printf.sprintf "Failed to parse memory: %s" msg)
  | e -> Error (Printf.sprintf "Unexpected error: %s" (Printexc.to_string e))

let save_to_file mem path =
  try
    let json = to_yojson mem in
    let json_string = Yojson.Safe.pretty_to_string json in
    let oc = open_out path in
    Fun.protect
      ~finally:(fun () -> close_out_noerr oc)
      (fun () -> output_string oc json_string; Ok ())
  with e -> Error (Printf.sprintf "Failed to save state: %s" (Printexc.to_string e))

let load_from_file path =
  try
    if not (Sys.file_exists path) then
      Error (Printf.sprintf "State file not found: %s" path)
    else
      let ic = open_in path in
      Fun.protect
        ~finally:(fun () -> close_in_noerr ic)
        (fun () ->
          let json_string = really_input_string ic (in_channel_length ic) in
          let json = Yojson.Safe.from_string json_string in
          of_yojson json )
  with
  | Yojson.Json_error msg -> Error (Printf.sprintf "Failed to parse state file: %s" msg)
  | e -> Error (Printf.sprintf "Failed to load state: %s" (Printexc.to_string e))
