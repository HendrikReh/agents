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

(** {1 State Persistence} *)

val to_yojson : t -> Yojson.Safe.t
(** [to_yojson mem] serializes memory state to JSON.

    The JSON schema includes:
    - version: Schema version number (currently 1)
    - goal: The agent's goal string
    - status: Current execution status (in_progress/completed/failed)
    - last_result: Last result string or null
    - iterations: Number of cycles executed
    - variables: List of key-value pairs *)

val of_yojson : Yojson.Safe.t -> (t, string) result
(** [of_yojson json] deserializes memory state from JSON.
    Returns [Ok memory] on success or [Error msg] on failure. *)

val save_to_file : t -> string -> (unit, string) result
(** [save_to_file mem path] saves memory state to a JSON file.
    Returns [Ok ()] on success or [Error msg] on failure.
    The file is written with pretty-printing for readability. *)

val load_from_file : string -> (t, string) result
(** [load_from_file path] loads memory state from a JSON file.
    Returns [Ok memory] on success or [Error msg] on failure.
    Validates the file exists and the JSON schema is correct. *)


