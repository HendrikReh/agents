# Repository Guidelines

## Project Structure & Module Organization
The core OCaml library lives in `lib/`, with small, focused modules for planning (`planner.ml`), execution (`executor.ml`), tooling (`tools.ml`), the OpenAI client, and shared state in `memory.ml`. Keep new functionality modular and remember to register each module inside `lib/dune`. The `bin/` directory houses the Cmdliner entry point (`main.ml`) that wires the agent together and loads environment configuration. Tests belong in `test/`, ideally mirroring library modules (for example, `test_planner.ml`). Dune build outputs under `_build/` and opam switches under `_opam/` are local artifacts and must stay untracked.

## Build, Test, and Development Commands
- `opam install . --deps-only` — sync required packages into the current opam switch.
- `dune build` — compile the library and CLI; append `@install` to verify install targets.
- `dune exec bin/agents.exe -- --goal "Plan the data ingest"` — run the agent locally after loading `.env`.
- `dune runtest` — execute the full test suite; add `--watch` for continuous feedback while iterating.

## Coding Style & Naming Conventions
Follow the established two-space indentation and keep lines under roughly 90 characters. Modules use `CamelCase`, while values, functions, and fields use `snake_case`. Favor descriptive record labels instead of tuples and make pattern matches exhaustive. Run `ocamlformat` (>=0.26) before committing—`dune fmt` will enforce formatting once the repo carries a `.ocamlformat` file. Handle `Lwt_result` branches explicitly to surface errors cleanly.

## Testing Guidelines
Add unit or integration coverage under `test/`, using deterministic inputs and stubbed OpenAI clients to avoid real network calls. Name scenarios `test_<behavior>` and expose them through the module referenced by `test/dune`. Focus on planner loop termination, executor/tool interactions, and error propagation. When adding new features, include tests that fail without the change and pass afterward.

## Commit & Pull Request Guidelines
Write imperative, component-scoped commit subjects (e.g., `planner: cap cycle count`). Use bodies to capture context, API notes, or follow-up tasks, and reference issues with `Fixes #123` when closing tickets. Pull requests should summarize intent, call out design notes, document test coverage (`dune build`, `dune runtest`, manual runs), and include CLI screenshots or logs if behavior changes.

## Security & Configuration Tips
Store secrets only in `.env` (e.g., `OPENAI_API_KEY`) and never commit the file. Document any new configuration knobs in your PR. When introducing tools that depend on external services, provide a mock implementation and gate live calls behind configuration so the default test path remains offline.
