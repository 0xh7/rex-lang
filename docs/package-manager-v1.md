# Rex Package Manager v1

This document records the package-manager scope for Rex v1.
The goal is a small, predictable workflow for real projects, not a full package ecosystem on day one.

## Goals

- Keep the language style explicit and simple.
- Add a real project manifest workflow before adding a package ecosystem.
- Support local development dependencies first.
- Add git-pinned dependencies without introducing registry complexity.
- Avoid building a Cargo clone.

## Non-Goals for v1

- No public registry.
- No feature flags.
- No workspaces.
- No semantic-version solver.
- No remote publishing flow.

## Project Files

Rex v1 project metadata is stored in:

- `rex.toml`
- `rex.lock`

Minimal manifest:

```toml
name = "app"
version = "0.1.0"
entry = "src/main.rex"
```

Dependencies are stored under:

```toml
[dependencies]
utils = "../utils"
json_tools = "../json-tools"
cli = "git+https://github.com/example/rex-cli#rev=abc123"
```

## Implementation Phases

### Phase 0: Manifest-Aware CLI

Status: implemented

Scope:

- `rex init` writes a manifest with `entry`.
- `rex build`, `rex run`, `rex fmt`, `rex lint`, and `rex check` resolve their default input from `entry`.
- Project root is discovered by walking upward until `rex.toml` is found.

### Phase 1: Local Path Dependencies

Status: implemented

Scope:

- `rex add <name> --path <path>`
- `rex remove <name>`
- `rex deps`
- `rex install`
- `rex.lock` generation
- local path validation
- nested dependency discovery
- cycle detection

This phase exists to stabilize:

- manifest shape
- CLI behavior
- dependency naming rules
- lockfile format

### Phase 2: Dependency Resolution

Status: implemented

Scope:

- resolve local path dependencies from `[dependencies]`
- make package roots visible to the compiler
- define import rules for package modules

Current supported import model:

- import dependency modules with:
  - `use libmath`
  - `use libmath as lm`
- call exported dependency functions with:
  - `lm.answer()`
- construct exported dependency structs with:
  - `lm.Point.new(1, 2)`
- construct exported dependency enum variants with:
  - `lm.Status.Ready`
  - `lm.Status.Code(7)`
- refer to exported dependency types in signatures with:
  - `lm::Point`
  - `lm::Status`
  - `lm::Count`

Current limitations:

- only public exports from the dependency entry file are visible
- dependency entry files currently support `use`, `fn`, `struct`, `enum`, `type`, and `impl`
- package imports currently expose:
  - `pub fn`
  - `pub struct`
  - `pub enum`
  - `pub type`
- package-aware struct literals are not implemented yet; use constructors for imported structs
- dependency type names must remain unique across the resolved graph for now
- package imports are single-segment module imports for now

### Phase 3: Git Dependencies

Status: implemented

Scope:

- `rex add <name> --git <url> --rev <revision>`
- pinned revision support
- cache checkout during `rex install`
- lockfile generation for git sources

### Phase 4: Optional Hosted Service

Planned scope:

- optional private package service
- may be hosted on the existing VPS later if needed
- not required for Rex v1

## Current CLI Surface

Implemented:

- `rex init <dir>`
- `rex add <name> --path <path>`
- `rex add <name> --git <url> --rev <revision>`
- `rex remove <name>`
- `rex deps`
- `rex install`

Current behavior:

- `rex add` updates `rex.toml`
- `rex remove` removes from `rex.toml`
- `rex deps` resolves local and git dependencies recursively
- `rex install` validates the tree, fetches git dependencies into cache, and writes `rex.lock`
- compiler-side package imports work for public functions and public types exported from dependency entry files

## Design Rules

- Prefer explicit manifests over inference-heavy workflows.
- Prefer local-path development before registry complexity.
- Prefer stable project commands over large syntax additions.
- Prefer a small package manager that can grow later.
