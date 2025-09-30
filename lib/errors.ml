(** Common error types for the agent system *)

type agent_error =
  | Planning_error of string
  | Execution_error of string
  | Tool_error of {
      tool : string;
      message : string;
    }
  | Max_iterations_exceeded of {
      limit : int;
      goal : string;
    }
  | No_answer_produced
  | Api_error of {
      code : int;
      message : string;
    }
  | Parse_error of string

let to_string = function
  | Planning_error msg -> Printf.sprintf "Planning error: %s" msg
  | Execution_error msg -> Printf.sprintf "Execution error: %s" msg
  | Tool_error { tool; message } ->
    Printf.sprintf "Tool '%s' error: %s" tool message
  | Max_iterations_exceeded { limit; goal } -> 
    Printf.sprintf "Max iterations (%d) exceeded for goal: %s" limit goal
  | No_answer_produced -> "Agent finished without producing an answer"
  | Api_error { code; message } ->
    Printf.sprintf "API error %d: %s" code message
  | Parse_error msg -> Printf.sprintf "Parse error: %s" msg

(** Result type alias for convenience *)
type 'a result = ('a, agent_error) Result.t
