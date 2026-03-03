# Rex CLI Reference

CLI command reference.

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

## 2. `build`

Parse + typecheck + generate C, and (by default) compile native binary.

```bash
rex build [input] [options]
```

Default input:
- `src/main.rex`

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

## 3. `run`

Build then execute a Rex file.

```bash
rex run [input] [options]
```

Default input:
- `src/main.rex`

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

## 4. `bench`

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

## 5. `test`

Build all example files to C.

```bash
rex test
```

This validates parsing/typechecking/codegen across the full example set,
including regression samples for newer syntax such as struct literals,
compound assignment, and richer `match` arms.

## 6. `fmt`

Format a source file (currently trims trailing spaces and normalizes ending newline).

```bash
rex fmt [input]
```

Default input:
- `src/main.rex`

## 7. `lint`

Run parser + typechecker validation.

```bash
rex lint [input]
```

Default input:
- `src/main.rex`

## 8. `check`

Same validation pipeline as lint, intended as quick correctness check.

```bash
rex check [input]
```

Default input:
- `src/main.rex`

Example:

```bash
rex check examples/test_multi_match.rex
```

## 9. Build Modes

- `release`: optimized build (default)
- `debug`: debug-friendly build flags

You can also set mode through environment:
- `REX_BUILD_MODE`
- `REX_MODE`

## 10. Environment Variables

- `CC`: default C compiler
- `REX_BUILD_MODE` / `REX_MODE`: default build mode
- `REX_CFLAGS`: extra C compiler flags
- `REX_OPT_FLAG`: override optimization behavior

## 11. Include Preprocessing

Before lexing/parsing, Rex can expand includes using comments:

```rex
// @include "relative/path.rex"
```

Include cycles are detected and reported as errors.
