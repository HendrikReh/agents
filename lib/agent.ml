let ( let* ) = Lwt_result.bind

type t = {
  planner : Planner.t;
  executor : Executor.t;
  max_cycles : int;
}

let create ?(max_cycles = 4) ~planner ~executor () = { planner; executor; max_cycles }

let rec loop_cycles t ~goal ~memory cycle =
  if cycle >= t.max_cycles then
    Lwt_result.fail
      (Printf.sprintf "Reached max planner cycles (%d) without finishing" t.max_cycles)
  else
    let* plan = Planner.plan t.planner ~goal ~memory in
    let* memory_after, finished = Executor.execute t.executor plan ~memory ~goal in
    if finished then
      Lwt_result.return memory_after
    else
      loop_cycles t ~goal ~memory:memory_after (succ cycle)

let run t goal =
  let memory = Memory.init goal in
  let* final_memory = loop_cycles t ~goal ~memory 0 in
  match Memory.get_answer final_memory with
  | Some answer -> Lwt_result.return answer
  | None -> (
      match Memory.last_result final_memory with
      | Some last -> Lwt_result.return last
      | None -> Lwt_result.fail "Agent finished without producing an answer")
