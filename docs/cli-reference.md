# Rex CLI Reference

This is the command surface implemented in the current tree.
Examples use the installed `rex` form, then show the source-checkout form where it matters.

Command forms:

```bash
rex <command> ...
```

Source checkout form:

```bash
cd rex
lua compiler/cli/rex.lua <command> ...
```

Examples use the installed form (`rex ...`).

## 1. `init`

Create a new project skeleton.

```bash
rex init <dir>
```

Creates:
- `<dir>/rex.toml`
- `<dir>/src/main.rex`

The generated manifest includes:
- `entry = "src/main.rex"`

## 2. `build`

Parse + typecheck + generate C, and (by default) compile native binary.

```bash
rex build [input] [options]
```

Default input:
- explicit `[input]` if provided
- otherwise `entry` from `rex.toml` in the current project root
- fallback: `src/main.rex`

Options:
- `--out <path>`: native output path
- `--c-out <path>`: generated C output path
- `--no-entry`: generate code without `main` entry wrapper
- `--no-native`: skip native compilation (generate C only)
- `--cc <compiler>`: C compiler command
- `--mode release|debug`: build mode

Examples:

```bash
rex build examples/hello.rex
rex build examples/hello.rex --no-native --c-out build/hello.c
rex build src/main.rex --mode debug --cc clang
```

## 3. `add`

Add a dependency to `rex.toml`.

```bash
rex add [name] --path <path>
rex add [name] --git <url> --rev <revision>
```

Notes:
- if `<name>` is omitted, Rex infers it from the path segment or git repo name
- git dependencies must be pinned with `--rev`

Example:

```bash
rex add utils --path ../utils
rex add jsonx --git https://github.com/example/jsonx --rev 4e2d9f1
```

## 4. `remove`

Remove a dependency from `rex.toml`.

```bash
rex remove <name>
```

Example:

```bash
rex remove utils
```

## 5. `install`

Validate dependencies and write `rex.lock`.

```bash
rex install
```

Current scope:
- validates each path or git dependency
- loads nested dependencies
- fetches git dependencies into the Rex package cache
- detects dependency cycles
- writes a lockfile snapshot
- enables compiler-side package imports for dependency entry files

Current import model:

```rex
use libmath as lm

fn main() {
    println(lm.answer())
}
```

Current exported package surface:
- `pub fn` through `pkg.fn()`
- `pub struct` through `pkg.Type.new(...)`
- `pub enum` through `pkg.Enum.Variant(...)` or `pkg.Enum.Variant`
- `pub type` through `pkg::Alias` in type positions

Current limitations:
- imported struct literals are not package-qualified yet; use constructors
- dependency type names must stay unique across the resolved graph for now

## 6. `deps`

Print the resolved dependency list for the current project.

```bash
rex deps
```

## 7. `run`

Build then execute a Rex file.

```bash
rex run [input] [options]
```

Default input:
- explicit `[input]` if provided
- otherwise `entry` from `rex.toml` in the current project root
- fallback: `src/main.rex`

Options:
- `--out <path>`
- `--c-out <path>`
- `--cc <compiler>`
- `--mode release|debug`

Example:

```bash
rex run examples/hello.rex
rex run examples/test_struct_lit.rex
```

## 8. `bench`

Run benchmark file multiple times and report elapsed stats.

```bash
rex bench [input] [options]
```

Default input:
- `examples/benchmark.rex`

Options:
- `--runs <n>` (must be >= 1)
- `--cc <compiler>`
- `--mode release|debug`

Example:

```bash
rex bench examples/benchmark.rex --runs 10
```

## 9. `test`

Build all example files to C.

```bash
rex test
```

This validates parsing/typechecking/codegen across the full example set,
including regression samples for newer syntax such as struct literals,
compound assignment, and richer `match` arms.

## 10. `fmt`

Format a source file (currently trims trailing spaces and normalizes ending newline).

```bash
rex fmt [input]
```

Default input:
- explicit `[input]` if provided
- otherwise `entry` from `rex.toml` in the current project root
- fallback: `src/main.rex`

## 11. `lint`

Run parser + typechecker validation.

```bash
rex lint [input]
```

Default input:
- explicit `[input]` if provided
- otherwise `entry` from `rex.toml` in the current project root
- fallback: `src/main.rex`

## 12. `check`

Same validation pipeline as lint, intended as quick correctness check.

```bash
rex check [input]
```

Default input:
- explicit `[input]` if provided
- otherwise `entry` from `rex.toml` in the current project root
- fallback: `src/main.rex`

Example:

```bash
rex check examples/test_multi_match.rex
```

## 13. Build Modes

- `release`: optimized build (default)
- `debug`: debug-friendly build flags

You can also set mode through environment:
- `REX_BUILD_MODE`
- `REX_MODE`

## 14. Environment Variables

- `CC`: default C compiler
- `REX_BUILD_MODE` / `REX_MODE`: default build mode
- `REX_CFLAGS`: extra C compiler flags
- `REX_OPT_FLAG`: override optimization behavior

## 15. Include Preprocessing

Before lexing/parsing, Rex can expand includes using comments:

```rex
// @include "relative/path.rex"
```

Include cycles are detected and reported as errors.
