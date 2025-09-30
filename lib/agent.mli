(** Main agent module that orchestrates planning and execution *)

(** Abstract type representing an agent instance *)
type t

(** [create ?max_cycles ~planner ~executor ()] creates a new agent.
    @param max_cycles Maximum planning cycles before termination (default: 4)
    @param planner The planner component to use
    @param executor The executor component to use *)
val create : ?max_cycles:int -> planner:Planner.t -> executor:Executor.t -> unit -> t

(** [run agent goal] runs the agent with the given goal.
    Returns the final answer or an error message. *)
val run : t -> string -> (string, string) result Lwt.t

(** [run_with_memory agent memory] runs the agent with pre-existing memory state.
    This allows resuming from a saved checkpoint or continuing a previous execution.
    Returns a tuple of (final_answer, final_memory) or an error message.

    The agent will continue from the iteration count stored in the memory,
    useful for resuming interrupted executions or branching from saved states. *)
val run_with_memory : t -> Memory.t -> (string * Memory.t, string) result Lwt.t
