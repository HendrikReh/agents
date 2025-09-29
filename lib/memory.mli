(** Agent memory module for managing state, variables, and execution status *)

type status =
  | In_progress
  | Completed of string
  | Failed of string

type t
(** Abstract type for agent memory *)

val init : string -> t
(** [init goal] creates a new memory instance with the given goal *)

val bump_iteration : t -> unit
(** Increment the iteration counter *)

val iterations : t -> int
(** Get the current iteration count *)

val goal : t -> string
(** Get the agent's goal *)

val status : t -> status
(** Get the current execution status *)

val set_status : t -> status -> unit
(** Set the execution status *)

val get_variable : t -> string -> Yojson.Safe.t option
(** [get_variable mem key] retrieves a variable from memory *)

val set_variable : t -> string -> Yojson.Safe.t -> unit
(** [set_variable mem key value] stores a variable in memory *)

val set_variable_string : t -> string -> string -> unit
(** [set_variable_string mem key value] stores a string variable *)

val last_result : t -> string option
(** Get the last result stored in memory *)

val set_last_result : t -> string -> unit
(** Set the last result *)

val data_snapshot : t -> (string * Yojson.Safe.t) list
(** Get a snapshot of all variables as an association list *)

val summary : t -> string
(** Get a human-readable summary of the memory state *)

val mark_completed : t -> string -> unit
(** [mark_completed mem answer] marks the agent as completed with the given answer *)

val mark_failed : t -> reason:string -> unit
(** [mark_failed mem ~reason] marks the agent as failed with the given reason *)

val ensure_default : t -> string -> Yojson.Safe.t -> unit
(** [ensure_default mem key value] sets a variable only if it doesn't exist *)

val get_answer : t -> string option
(** Extract the final answer from memory if available *)


