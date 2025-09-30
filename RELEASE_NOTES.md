# Release Notes - v0.0.3

**Release Date:** September 30, 2025
**Status:** Proof of Concept
**License:** MIT

---

## Overview

OCaml Agents is a LangGraph-inspired planner/executor agent system implemented in OCaml using Lwt for asynchronous execution. This release represents a production-ready proof of concept with comprehensive testing, state persistence, structured logging, and full CI/CD integration.

## What's New in v0.0.3

### Core Features

#### **Agent Orchestration**
- **Modular architecture** with clean separation between planning, execution, and memory
- **Asynchronous execution** built on Lwt for non-blocking operations
- **Flexible planning** with support for actions, branching, loops, and conditional execution
- **Type-safe** design leveraging OCaml's strong type system
- **Maximum cycle control** with configurable iteration limits (default: 4 cycles)

#### **State Persistence**
- **Save/resume capabilities** for long-running tasks
- **JSON-based serialization** with versioned schema
- **Checkpoint support** for debugging and branching workflows
- **Programmatic API** for state management (`Memory.save_to_file`, `Memory.load_from_file`)

```bash
# Save state after execution
dune exec agents -- --goal "complex task" --save-state state.json

# Resume from saved state
dune exec agents -- --load-state state.json
```

#### **Structured Logging**
- **Multiple log levels**: debug, info, warning, error, app, quiet
- **Per-module sources** for granular control (agent, planner, executor, openai, memory)
- **Colored terminal output** with ANSI formatting
- **CLI integration** via `--log-level` flag

```bash
dune exec agents -- --goal "task" --log-level debug
```

### Testing & Quality Assurance

#### **Comprehensive Test Suite**
- **26 test cases** covering 558 lines of test code
- **Fast & deterministic** - all tests run in milliseconds
- **No network dependencies** - stubbed OpenAI client for offline testing
- **Alcotest framework** for clear test organization and reporting
- **Coverage includes:**
  - Memory operations (CRUD, persistence, error paths)
  - Node parsing (actions, branches, conditions)
  - Executor logic (conditions, loops, actions)
  - Planner integration (JSON parsing, schema validation)
  - Error handling and edge cases

```bash
dune runtest                    # Run all tests
ALCOTEST_VERBOSE=1 dune runtest # Verbose output
ALCOTEST_QUICK_TESTS=1 dune runtest # Quick subset
```

#### **Continuous Integration**
- **GitHub Actions** with matrix builds (Ubuntu/macOS × OCaml 5.1/5.2)
- **Format checking** via ocamlformat 0.26.2
- **Lint job** with warning-as-error enforcement
- **Local CI testing** via nektos/act with automatic OCaml setup detection
- **Build status badge** in README

### Developer Experience

#### **Local Workflow Testing**
- **act integration** for running GitHub Actions locally
- **Automatic detection** of act environment with graceful degradation
- **Comprehensive documentation** including troubleshooting guide
- **~/.actrc configuration** examples for Apple Silicon compatibility

```bash
# Run lint job locally
act push -j lint

# Run specific matrix job
act push -j build --matrix os=ubuntu-latest,ocaml-compiler=5.2.x
```

#### **Code Quality**
- **OCamlformat configuration** for consistent style
- **Module interfaces** (.mli files) for all public APIs
- **Structured error types** replacing string-based errors
- **Type-safe JSON handling** via Yojson
- **Proper resource cleanup** with Fun.protect patterns

#### **Documentation**
- **README.md** with badges, quick start, and examples
- **docs/DEVELOPER.md** with detailed guides for:
  - Logging system and usage
  - State persistence workflows
  - Testing philosophy and execution
  - Local CI with act (installation, configuration, troubleshooting)
  - OpenAI API configuration and model support
- **CLAUDE.md** for AI-assisted development guidance
- **docs/GUIDELINES.md** for contribution standards

### OpenAI Integration

#### **API Client**
- **HTTP/HTTPS support** via cohttp-lwt-unix
- **GPT-5 compatibility** with automatic temperature parameter handling
- **Error handling** with structured error types and status codes
- **Model override** via `--model` CLI flag
- **Environment-based** API key configuration (.env file)

#### **Temperature Handling**
- **GPT-5 models**: Automatically excludes temperature parameter
- **Other models** (tbd): Configurable temperature
  - Planner default: 0.1 (deterministic)
  - Executor default: 0.2 (slightly creative)
- **Logging reflection** shows actual parameters sent to API

### Project Structure

```
agents/
├── lib/                    # Core library (~1,016 LOC)
│   ├── agent.ml/.mli       # Main orchestrator
│   ├── planner.ml          # Plan generation
│   ├── executor.ml         # Plan execution
│   ├── memory.ml/.mli      # State management
│   ├── nodes.ml            # Plan structure types
│   ├── openai_client.ml    # API client
│   ├── errors.ml           # Error types
│   ├── logging.ml          # Log sources
│   └── tools.ml            # Utilities
├── bin/
│   └── main.ml             # CLI entry point
├── test/
│   └── test_agents.ml      # Test suite (558 LOC, 26 tests)
├── docs/
│   ├── DEVELOPER.md        # Developer guide
│   └── GUIDELINES.md       # Contribution guide
├── .github/workflows/
│   └── ci.yml              # CI/CD pipeline
├── .ocamlformat            # Code style config
├── .gitignore              # VCS ignore rules
├── dune-project            # Project metadata
└── README.md               # User documentation
```

### Key Modules

#### **Agent Module**
- Orchestrates planning and execution cycles
- Manages cycle limits and completion detection
- Provides `run` and `run_with_memory` APIs

#### **Planner Module**
- Generates JSON-based execution plans
- Strips code fences from LLM responses
- Validates against schema
- Supports actions, branches, loops, and finish nodes

#### **Executor Module**
- Executes plans node-by-node
- Evaluates conditions (Always, Has_variable, Equals, Not, etc.)
- Manages iteration limits for loops
- Updates memory with action results

#### **Memory Module**
- Manages goal, variables, status, and results
- Provides JSON serialization/deserialization
- Supports file-based persistence
- Tracks iteration count for cycle management

#### **Nodes Module**
- Defines plan structure types
- Condition evaluation logic
- JSON parsing with graceful error handling

### Quality Metrics

- **Test Coverage**: 26 test cases covering all major code paths
- **Code Style**: 100% formatted with ocamlformat
- **Type Safety**: Comprehensive .mli interfaces for public APIs
- **Error Handling**: Structured Result types throughout
- **CI/CD**: Full matrix testing on Ubuntu and macOS
- **Documentation**: ~500+ lines across multiple guides

## Dependencies

- **OCaml**: >= 5.1
- **Runtime**: lwt, cohttp-lwt-unix, uri, yojson
- **CLI**: cmdliner
- **Logging**: logs, fmt
- **Testing**: alcotest (test-only)
- **Formatting**: ocamlformat 0.26.2 (dev-only)

## Installation

```bash
# Clone repository
git clone https://github.com/HendrikReh/agents.git
cd agents

# Install dependencies
opam install . --deps-only

# Build
dune build

# Configure API key
echo "OPENAI_API_KEY=your-key" > .env

# Run
dune exec agents -- --goal "Your task here"
```

## Usage Examples

### Basic Execution
```bash
dune exec agents -- --goal "Research quantum computing trends"
```

### With Custom Model and Logging
```bash
dune exec agents -- \
  --goal "Analyze OCaml ecosystem" \
  --model gpt-5 \
  --log-level debug \
  --max-cycles 10
```

### State Persistence Workflow
```bash
# Initial run with checkpoint
dune exec agents -- \
  --goal "Multi-step analysis task" \
  --save-state checkpoint.json

# Resume and continue
dune exec agents -- \
  --load-state checkpoint.json \
  --save-state checkpoint.json
```

## Platform Support

- **Operating Systems**: Linux, macOS, Windows (via WSL)
- **OCaml Versions**: 5.1.x, 5.2.x
- **CI Testing**: Ubuntu 22.04, macOS latest
- **Docker**: Compatible with ocaml/opam images

## Known Limitations

1. **Tool Support**: Currently only LLM tool is implemented
2. **State Size**: Large variable sets can create large JSON files
3. **No Auto-Checkpointing**: Manual save required between runs
4. **API Key Management**: No rotation or encryption support
5. **act Compatibility**: setup-ocaml@v3 action requires workaround for local testing

### Planned Enhancements

- Additional tools (search, calculator, file operations)
- Retry logic with exponential backoff
- Token usage tracking and cost monitoring
- Interactive CLI mode
- Property-based testing with QCheck
- API documentation generation via odoc

## Breaking Changes

None (first stable PoC release)

## Migration Guide

N/A (initial release)

## Contributors

- Hendrik Reh <hendrik.reh@outlook.com>
- Claude (AI pair programming assistant)

## Acknowledgments

- Inspired by [LangGraph](https://www.langchain.com/langgraph)
- Built with [Lwt](https://ocsigen.org/lwt/)
- Tested with [Alcotest](https://github.com/mirage/alcotest)
- Powered by [OpenAI](https://platform.openai.com/)

## Links

- **Repository**: https://github.com/HendrikReh/agents
- **Issues**: https://github.com/HendrikReh/agents/issues
- **CI/CD**: https://github.com/HendrikReh/agents/actions
- **License**: MIT

---

**Full Changelog**: https://github.com/HendrikReh/agents/commits/main