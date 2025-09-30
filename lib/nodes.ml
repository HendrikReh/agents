(* Planner node definitions capturing actions, branching, and looping. *)

type condition =
  | Always
  | Has_variable of string
  | Not_has_variable of string
  | Equals of {
      key : string;
      value : string;
    }
  | Not of condition

let rec condition_to_string = function
  | Always -> "always"
  | Has_variable key -> Printf.sprintf "has_variable(%s)" key
  | Not_has_variable key -> Printf.sprintf "not_has_variable(%s)" key
  | Equals { key; value } -> Printf.sprintf "equals(%s,%s)" key value
  | Not cond -> "not(" ^ condition_to_string cond ^ ")"

type action = {
  id : string;
  label : string;
  tool : string option;
  prompt : string;
  save_as : string option;
}

type branch = {
  id : string;
  condition : condition;
  if_true : node list;
  if_false : node list;
}

and loop = {
  id : string;
  condition : condition;
  body : node list;
  max_iterations : int option;
}

and finish = {
  id : string;
  summary : string option;
}

and node =
  | Action of action
  | Branch of branch
  | Loop of loop
  | Finish of finish

and plan = node list

exception Parse_error of string

let parse_errorf fmt = Printf.ksprintf (fun msg -> raise (Parse_error msg)) fmt

let string_field assoc field =
  match List.assoc_opt field assoc with
  | Some (`String s) -> s
  | Some _ -> parse_errorf "Field '%s' must be string" field
  | None -> parse_errorf "Missing string field '%s'" field

let opt_string_field assoc field =
  match List.assoc_opt field assoc with
  | Some (`String s) -> Some s
  | Some `Null -> None
  | Some _ -> parse_errorf "Field '%s' must be string or null" field
  | None -> None

let int_opt_field assoc field =
  match List.assoc_opt field assoc with
  | Some (`Int i) -> Some i
  | Some (`Float f) -> Some (int_of_float f)
  | Some `Null -> None
  | Some _ -> parse_errorf "Field '%s' must be int" field
  | None -> None

let rec condition_of_yojson = function
  | `Assoc fields as json -> (
    match List.assoc_opt "type" fields with
    | Some (`String "always") -> Always
    | Some (`String "has_variable") ->
      let key = string_field fields "key" in
      Has_variable key
    | Some (`String "not_has_variable") ->
      let key = string_field fields "key" in
      Not_has_variable key
    | Some (`String "equals") ->
      let key = string_field fields "key" in
      let value = string_field fields "value" in
      Equals { key; value }
    | Some (`String "not") ->
      let nested =
        match List.assoc_opt "condition" fields with
        | Some cond -> condition_of_yojson cond
        | None -> parse_errorf "Missing 'condition' field inside NOT"
      in
      Not nested
    | Some (`String other) -> parse_errorf "Unsupported condition type '%s'" other
    | Some _ -> parse_errorf "Condition 'type' must be string"
    | None ->
      parse_errorf "Condition must contain 'type': %s" (Yojson.Safe.to_string json) )
  | json -> parse_errorf "Condition must be object, got %s" (Yojson.Safe.to_string json)

and node_of_yojson = function
  | `Assoc fields as json -> (
    match List.assoc_opt "type" fields with
    | Some (`String "action") ->
      let label =
        match List.assoc_opt "label" fields with
        | Some (`String s) -> s
        | _ -> (
          match List.assoc_opt "description" fields with
          | Some (`String s) -> s
          | _ -> string_field fields "id" )
      in
      let action =
        {
          id = string_field fields "id";
          label;
          tool = opt_string_field fields "tool";
          prompt = string_field fields "prompt";
          save_as = opt_string_field fields "save_as";
        }
      in
      Action action
    | Some (`String "branch") ->
      let condition =
        match List.assoc_opt "condition" fields with
        | Some cond -> condition_of_yojson cond
        | None -> parse_errorf "Branch missing condition"
      in
      let branch =
        {
          id = string_field fields "id";
          condition;
          if_true =
            ( match List.assoc_opt "if_true" fields with
            | Some (`List lst) -> List.map node_of_yojson lst
            | Some _ -> parse_errorf "Branch 'if_true' must be list"
            | None -> [] );
          if_false =
            ( match List.assoc_opt "if_false" fields with
            | Some (`List lst) -> List.map node_of_yojson lst
            | Some _ -> parse_errorf "Branch 'if_false' must be list"
            | None -> [] );
        }
      in
      Branch branch
    | Some (`String "loop") ->
      let condition =
        match List.assoc_opt "condition" fields with
        | Some cond -> condition_of_yojson cond
        | None -> parse_errorf "Loop missing condition"
      in
      let loop =
        {
          id = string_field fields "id";
          condition;
          body =
            ( match List.assoc_opt "body" fields with
            | Some (`List lst) -> List.map node_of_yojson lst
            | Some _ -> parse_errorf "Loop 'body' must be list"
            | None -> [] );
          max_iterations = int_opt_field fields "max_iterations";
        }
      in
      Loop loop
    | Some (`String "finish") ->
      let finish =
        { id = string_field fields "id"; summary = opt_string_field fields "summary" }
      in
      Finish finish
    | Some (`String other) -> parse_errorf "Unsupported node type '%s'" other
    | Some _ -> parse_errorf "Node 'type' must be string"
    | None -> parse_errorf "Node missing 'type': %s" (Yojson.Safe.to_string json) )
  | json -> parse_errorf "Node must be object, got %s" (Yojson.Safe.to_string json)

let plan_of_yojson json =
  match json with
  | `Assoc fields -> (
    match List.assoc_opt "plan" fields with
    | Some (`List nodes) -> List.map node_of_yojson nodes
    | Some _ -> parse_errorf "'plan' must be list"
    | None -> (
      match List.assoc_opt "nodes" fields with
      | Some (`List nodes) -> List.map node_of_yojson nodes
      | Some _ -> parse_errorf "'nodes' must be list"
      | None -> parse_errorf "Plan JSON must contain 'plan' or 'nodes'" ) )
  | `List nodes -> List.map node_of_yojson nodes
  | _ -> parse_errorf "Plan JSON must be object or list"

let pp_node fmt = function
  | Action a -> Format.fprintf fmt "Action(%s -> %s)" a.id a.label
  | Branch b ->
    Format.fprintf fmt "Branch(%s if %s)" b.id (condition_to_string b.condition)
  | Loop l ->
    Format.fprintf fmt "Loop(%s while %s)" l.id (condition_to_string l.condition)
  | Finish f -> Format.fprintf fmt "Finish(%s)" f.id

let pp_plan fmt plan =
  Format.fprintf fmt "[";
  List.iteri
    (fun idx node ->
      if idx > 0 then Format.fprintf fmt "; ";
      pp_node fmt node )
    plan;
  Format.fprintf fmt "]"
