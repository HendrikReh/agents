(** Main agent module that orchestrates planning and execution *)

type t
(** Abstract type representing an agent instance *)

val create : ?max_cycles:int -> planner:Planner.t -> executor:Executor.t -> unit -> t
(** [create ?max_cycles ~planner ~executor ()] creates a new agent.
    @param max_cycles Maximum planning cycles before termination (default: 4)
    @param planner The planner component to use
    @param executor The executor component to use *)

val run : t -> string -> (string, string) result Lwt.t
(** [run agent goal] runs the agent with the given goal.
    Returns the final answer or an error message. *)


