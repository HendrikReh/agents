# OCaml Agents (PoC)

[![OCaml](https://img.shields.io/badge/OCaml-%3E%3D%205.1-orange.svg)](https://ocaml.org)
[![Status](https://img.shields.io/badge/Status-Proof%20of%20Concept-yellow.svg)](https://github.com/HendrikReh/agents)
[![Build Status](https://img.shields.io/github/actions/workflow/status/HendrikReh/agents/ci.yml?branch=main)](https://github.com/HendrikReh/agents/actions)
[![License](https://img.shields.io/github/license/HendrikReh/agents)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](docs/GUIDELINES.md)
[![Maintenance](https://img.shields.io/badge/Maintained%3F-yes-green.svg)](https://github.com/HendrikReh/agents/graphs/commit-activity)

A LangGraph-inspired planner/executor agent system implemented in OCaml using Lwt for asynchronous execution.

<p align="center">
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#development">Development</a> •
  <a href="#contributing">Contributing</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Dependencies-Lwt%20%7C%20Yojson%20%7C%20Cohttp-blue.svg" alt="Dependencies">
  <img src="https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg" alt="Platform">
  <img src="https://img.shields.io/badge/Code%20Style-OCamlformat-blueviolet.svg" alt="Code Style">
  <img src="https://img.shields.io/badge/LangGraph-Inspired-ff69b4.svg" alt="LangGraph Inspired">
</p>

## Features

- **Modular Architecture**: Clean separation between planning, execution, and memory components
- **Asynchronous Execution**: Built on Lwt for non-blocking operations
- **Flexible Planning**: Support for actions, branching, loops, and conditional execution
- **Extensible Tools**: Easy to add new tools and integrations
- **Type-Safe**: Leverages OCaml's strong type system for reliability

## Installation

### Prerequisites

- OCaml >= 5.1
- opam package manager
- An OpenAI API key

### Setup

1. Clone the repository:
```bash
git clone https://github.com/HendrikReh/agents.git
cd agents
```

2. Install dependencies:
```bash
opam install . --deps-only
```

3. Build the project:
```bash
dune build
```

4. Create a `.env` file with your OpenAI API key:
```bash
echo "OPENAI_API_KEY=your-api-key-here" > .env
```

## Usage

Run the agent with a goal:

```bash
dune exec agents -- --goal "Research the latest developments in quantum computing"
```

### Command Line Options

- `--goal`: The goal/task for the agent to accomplish (required)
- `--max-cycles`: Maximum planning cycles (default: 4)
- `--model`: OpenAI model to use (default: gpt-5)

## Architecture

The system consists of several key modules:

- **Agent**: Main orchestration module that coordinates planning and execution
- **Planner**: Generates execution plans based on goals and current state
- **Executor**: Executes plans, handling actions, branches, and loops
- **Memory**: Manages agent state and variables
- **Nodes**: Defines the plan structure (actions, branches, loops, etc.)
- **OpenAI Client**: Handles LLM API interactions
- **Tools**: Utility functions for the agent system

## Development

### Testing

- `dune runtest` – runs the full Alcotest suite (all cases are fast/deterministic).
- `ALCOTEST_QUICK_TESTS=1 dune runtest` – run only tests marked as quick (current default).
- `ALCOTEST_VERBOSE=1 dune runtest` – stream captured output to the terminal for debugging.

Tests stub all OpenAI calls, so no network access or API keys are needed.

### Code Formatting

Once `.ocamlformat` is configured:
```bash
dune fmt
```

### Watch Mode

For development with automatic rebuilding:
```bash
dune build --watch
```

## Contributing

Please see [GUIDELINES.md](docs/GUIDELINES.md) for detailed contribution guidelines.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  <img src="https://img.shields.io/badge/Version-0.0.3-red.svg" alt="Version">
  <img src="https://img.shields.io/badge/Stage-Experimental-orange.svg" alt="Experimental">
  <img src="https://img.shields.io/badge/Made%20with-OCaml-orange.svg" alt="Made with OCaml">
  <img src="https://img.shields.io/badge/Powered%20by-OpenAI-412991.svg" alt="Powered by OpenAI">
  <img src="https://img.shields.io/github/last-commit/HendrikReh/agents" alt="Last Commit">
  <img src="https://img.shields.io/github/issues/HendrikReh/agents" alt="Issues">
  <img src="https://img.shields.io/github/stars/HendrikReh/agents?style=social" alt="Stars">
</p>
