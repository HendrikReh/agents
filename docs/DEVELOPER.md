# Developer Guide

## Logging

The project uses Daniel Bünzli's [Logs](https://erratique.ch/software/logs) library for structured logging throughout the agent system.

### Log Sources

Each major module has its own log source defined in `lib/logging.ml`:

- `agent` - Agent orchestrator (cycle management)
- `planner` - Plan generation and JSON parsing
- `executor` - Plan execution (actions, branches, loops)
- `openai` - OpenAI API client (HTTP requests/responses)
- `memory` - Agent memory operations

### Log Levels

Use the `--log-level` CLI flag to control verbosity:

```bash
dune exec agents -- --goal "your task" --log-level debug
```

Available levels (from most to least verbose):
- `debug` - Detailed execution flow (cyan color)
- `info` - High-level operations (blue color) **[default]**
- `warning` - Warnings and recoverable issues (yellow color)
- `error` - Errors and failures (red color)
- `app` - Application-level messages (no color)
- `quiet` - No logging output

### Color Output

Log messages are automatically colored by level when output to a terminal:
- The entire line (tag + message) is colored for better readability
- Colors are forced via `Fmt.set_style_renderer stderr_fmt \`Ansi_tty`

### Adding Logging to New Modules

1. Add your log source to `lib/logging.ml`:
```ocaml
let my_module_src = Logs.Src.create "mymodule" ~doc:"Description"
module MyModule = (val Logs.src_log my_module_src : Logs.LOG)
```

2. Use it in your module:
```ocaml
module Log = Logging.MyModule

let my_function () =
  Log.info (fun m -> m "Starting operation");
  Log.debug (fun m -> m "Detail: value=%d" some_value);
  Log.err (fun m -> m "Operation failed: %s" error_msg)
```

3. Register the module in `lib/dune` if needed.

## Testing

- `dune runtest` runs the entire Alcotest suite; all cases are deterministic and mock the OpenAI client.
- Negative-path coverage includes planner JSON/schema errors (missing plan nodes, bad types), executor loop limits/unsupported tools, and memory deserialization failures.
- Use `ALCOTEST_VERBOSE=1` while iterating on tests to stream captured output.

### Local CI with `act`

You can replay the GitHub Actions matrix locally:

1. Install [`act`](https://github.com/nektos/act) (e.g. `brew install act`).
2. On Apple Silicon, add a default config `~/.actrc` so the runner pulls x86_64 images:
   ```
   --container-architecture linux/amd64
   -P ubuntu-latest=catthehacker/ubuntu:act-latest
   -P macos-latest=catthehacker/ubuntu:act-latest
   ```
3. Run the workflow slice you care about, e.g. the linux/OCaml 5.2 job:
   ```bash
   act push -j build --matrix '{"os":"ubuntu-latest","ocaml-compiler":"5.2.x"}' \
       --container-architecture linux/amd64
   ```
   Repeat with `"5.1.x"` for the other compiler variant. The macOS matrix is large/slow; map it to the Ubuntu image (as above) or run it on GitHub’s runners instead.

Common troubleshooting: if you see `ReferenceError: File is not defined`, it means the container architecture wasn’t forced to `linux/amd64`. Adjust the config or pass `--container-architecture linux/amd64` explicitly.

## OpenAI API

### Model Support

The default model is `gpt-5`. You can override it with the `--model` flag:

```bash
dune exec agents -- --goal "task" --model gpt-4
```

### Temperature Handling

**Important**: GPT-5 models do not support the `temperature` parameter. The client automatically detects GPT-5 models (by prefix `gpt-5*`) and excludes the temperature parameter from API requests.

For other models (gpt-4, gpt-3.5-turbo, etc.), temperature is sent as specified:
- Planner default: `0.1` (more deterministic)
- Executor default: `0.2` (slightly more creative)

The logging reflects this behavior:
- GPT-5: `temperature=default` in logs
- Other models: `temperature=0.10` in logs

### Configuration

Create a `.env` file in the project root:

```bash
OPENAI_API_KEY=your-api-key-here
```

The API key is required for all operations.

## State Persistence

The agent supports saving and restoring execution state, enabling:
- **Pause and resume**: Stop execution and continue later
- **Debugging**: Inspect intermediate state at any cycle
- **Branching**: Fork from saved states to explore alternatives
- **Resilience**: Recover from crashes or interruptions

### JSON Schema

State is persisted as JSON with the following structure:

```json
{
  "version": 1,
  "goal": "The agent's goal string",
  "status": {
    "type": "in_progress|completed|failed",
    "answer": "result (if completed)",
    "reason": "error message (if failed)"
  },
  "last_result": "last execution result or null",
  "iterations": 2,
  "variables": [
    {"key": "variable_name", "value": <any JSON value>}
  ]
}
```

The schema includes a version number for future compatibility.

### CLI Usage

#### Save State

Save the final agent state after execution:

```bash
dune exec agents -- --goal "complex task" --save-state state.json
```

The state file will contain the complete memory including all variables, results, and cycle count.

#### Load State

Resume from a previously saved state:

```bash
dune exec agents -- --load-state state.json
```

The agent will:
- Restore the goal, variables, and iteration count
- Continue from the saved cycle number
- Complete any remaining work

#### Combined Save and Load

```bash
# First run - save state
dune exec agents -- --goal "multi-step task" --save-state progress.json

# Continue from where it left off
dune exec agents -- --load-state progress.json --save-state progress.json
```

### Programmatic API

#### Save Memory to File

```ocaml
let mem = Memory.init "Some goal" in
(* ... do work ... *)
match Memory.save_to_file mem "checkpoint.json" with
| Ok () -> Printf.printf "Saved successfully\n"
| Error msg -> Printf.eprintf "Save failed: %s\n" msg
```

#### Load Memory from File

```ocaml
match Memory.load_from_file "checkpoint.json" with
| Ok mem ->
    Printf.printf "Loaded goal: %s\n" (Memory.goal mem);
    Printf.printf "At cycle: %d\n" (Memory.iterations mem)
| Error msg ->
    Printf.eprintf "Load failed: %s\n" msg
```

#### Run Agent with Restored Memory

```ocaml
match Memory.load_from_file "state.json" with
| Error msg -> Error msg
| Ok memory ->
    let client = Openai_client.create ~api_key () in
    let planner = Planner.create client in
    let executor = Executor.create client in
    let agent = Agent.create ~planner ~executor () in

    match Lwt_main.run (Agent.run_with_memory agent memory) with
    | Ok (answer, final_memory) ->
        (* Optionally save updated state *)
        let _ = Memory.save_to_file final_memory "state.json" in
        Ok answer
    | Error msg -> Error msg
```

### Use Cases

#### Long-Running Tasks

For tasks that may take multiple hours:

```bash
# Start task
dune exec agents -- --goal "analyze large dataset" --save-state analysis.json

# If interrupted, resume
dune exec agents -- --load-state analysis.json --save-state analysis.json
```

#### Debugging Agent Behavior

Inspect state at each cycle:

```bash
# Run with save
dune exec agents -- --goal "debug this" --save-state debug.json --log-level debug

# Examine the JSON file
cat debug.json | jq .

# Modify variables if needed and resume
dune exec agents -- --load-state debug.json
```

#### Experimenting with Different Approaches

Branch from a saved checkpoint:

```bash
# Initial approach
dune exec agents -- --goal "solve problem" --save-state base.json

# Try approach A
cp base.json approach_a.json
dune exec agents -- --load-state approach_a.json --save-state approach_a.json

# Try approach B
cp base.json approach_b.json
dune exec agents -- --load-state approach_b.json --save-state approach_b.json
```

### Implementation Details

- **Serialization**: Uses Yojson for JSON handling
- **Hashtable Conversion**: Variables are stored as Hashtbl but serialized as JSON arrays
- **Error Handling**: All file I/O uses `Result` types for explicit error handling
- **Schema Versioning**: Version field enables future format migrations
- **Atomic Writes**: Files are written with `Fun.protect` for proper resource cleanup

### Limitations

- State files can be large if many variables are stored
- No automatic checkpointing during execution (manual save only)
- No encryption (do not store sensitive data in variables)
- Goal cannot be changed when resuming (validated on load)

## Testing

### Philosophy

All tests live in `test/test_agents.ml` and are written with [Alcotest](https://github.com/mirage/alcotest). The guiding principles are:

- **Fast & deterministic** – every case runs in milliseconds so `dune runtest` stays snappy.
- **No live APIs** – LLM interactions are replaced with deterministic stubs, so CI never needs network access or secrets.
- **Black-box behaviour** – we test the public surface of each module (memory, nodes, executor, planner) instead of implementation details.
- **Single binary** – one test executable keeps the Dune setup simple while still grouping cases by suite inside Alcotest.

### Running the Suite

The default run executes every case:

```bash
dune runtest
```

To focus on the “quick” subset (all of our tests fall into this bucket today) you can use Alcotest’s built-in filter:

```bash
ALCOTEST_QUICK_TESTS=1 dune runtest
```

Verbose output (disables log capturing):

```bash
ALCOTEST_VERBOSE=1 dune runtest
```

To run the binary directly (useful for attaching a debugger):

```bash
dune exec test/test_agents.exe
```

### Test Coverage

The suite currently exercises:

- **Memory** – inits, variable CRUD, completion/failed flows, JSON round-trips, file persistence, and error paths.
- **Nodes** – Yojson parsers for actions and branches, including graceful failure cases.
- **Executor** – condition evaluation across all supported predicates and the LLM action path via a stubbed client.
- **Planner** – code fence stripping, relaxed JSON extraction, and end-to-end planning with a stubbed OpenAI chat.

Adding new behaviour? Please extend the relevant suite and keep tests stubbed/offline. If you introduce genuinely slow scenarios, mark them with `` `Slow`` and document how to skip them.