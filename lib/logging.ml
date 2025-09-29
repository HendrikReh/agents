(** Logging tags and sources for the agent system *)

let agent_src = Logs.Src.create "agent" ~doc:"Agent orchestrator"
let planner_src = Logs.Src.create "planner" ~doc:"Plan generation"
let executor_src = Logs.Src.create "executor" ~doc:"Plan execution"
let openai_src = Logs.Src.create "openai" ~doc:"OpenAI API client"
let memory_src = Logs.Src.create "memory" ~doc:"Agent memory"

module Agent = (val Logs.src_log agent_src : Logs.LOG)
module Planner = (val Logs.src_log planner_src : Logs.LOG)
module Executor = (val Logs.src_log executor_src : Logs.LOG)
module OpenAI = (val Logs.src_log openai_src : Logs.LOG)
module Memory = (val Logs.src_log memory_src : Logs.LOG)