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

## Testing

Run the test suite:

```bash
dune runtest
```

Tests use stubbed OpenAI clients (no real network calls) to ensure deterministic behavior.