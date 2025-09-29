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
  Hashtbl.fold
    (fun key value acc -> (key, value) :: acc)
    mem.variables
    []

let summary mem =
  let items =
    data_snapshot mem
    |> List.map (fun (k, v) ->
           let value_string =
             match v with
             | `String s -> s
             | _ -> Yojson.Safe.to_string v
           in
           Printf.sprintf "%s: %s" k value_string)
  in
  let items =
    if items = [] then
      "<empty>"
    else
      String.concat "; " items
  in
  Printf.sprintf
    "Goal: %s\nStatus: %s\nLast result: %s\nVariables: %s"
    mem.goal
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
  match get_variable mem key with
  | None -> set_variable mem key value
  | Some _ -> ()

let get_answer mem =
  match mem.status with
  | Completed answer -> Some answer
  | _ ->
      match get_variable mem "final_answer" with
      | Some (`String s) -> Some s
      | _ -> None
