let max_summary_length = 1200

let summary_excerpt memory =
  let text = Memory.summary memory in
  if String.length text > max_summary_length then
    String.sub text 0 (max_summary_length - 3) ^ "..."
  else text
