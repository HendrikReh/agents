let ( let* ) = Lwt_result.bind

module Log = Logging.Agent

type t = {
  planner : Planner.t;
  executor : Executor.t;
  max_cycles : int;
}

let create ?(max_cycles = 4) ~planner ~executor () =
  Log.info (fun m -> m "Creating agent with max_cycles=%d" max_cycles);
  { planner; executor; max_cycles }

let rec loop_cycles t ~goal ~memory cycle =
  if cycle >= t.max_cycles then (
    Log.warn (fun m ->
        m "Reached max planner cycles (%d) without finishing" t.max_cycles );
    Lwt_result.fail
      (Printf.sprintf "Reached max planner cycles (%d) without finishing" t.max_cycles)
  )
  else (
    Log.info (fun m -> m "Starting cycle %d/%d" (cycle + 1) t.max_cycles);
    let* plan = Planner.plan t.planner ~goal ~memory in
    let* memory_after, finished = Executor.execute t.executor plan ~memory ~goal in
    if finished then (
      Log.info (fun m -> m "Agent finished successfully at cycle %d" (cycle + 1));
      Lwt_result.return memory_after
    )
    else (
      Log.debug (fun m -> m "Cycle %d complete, continuing" (cycle + 1));
      loop_cycles t ~goal ~memory:memory_after (succ cycle)
    )
  )

let run_with_memory t memory =
  let goal = Memory.goal memory in
  let start_cycle = Memory.iterations memory in
  Log.info (fun m ->
      m "Running agent with goal: %s (starting at cycle %d)" goal start_cycle );
  let* final_memory = loop_cycles t ~goal ~memory start_cycle in
  match Memory.get_answer final_memory with
  | Some answer ->
    Log.info (fun m -> m "Agent completed with answer");
    Lwt_result.return (answer, final_memory)
  | None -> (
    match Memory.last_result final_memory with
    | Some last ->
      Log.debug (fun m -> m "Agent completed with last result");
      Lwt_result.return (last, final_memory)
    | None ->
      Log.err (fun m -> m "Agent finished without producing an answer");
      Lwt_result.fail "Agent finished without producing an answer"
  )

let run t goal =
  Log.info (fun m -> m "Running agent with goal: %s" goal);
  let memory = Memory.init goal in
  let* answer, _final_memory = run_with_memory t memory in
  Lwt_result.return answer
