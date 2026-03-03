# Examples Index

This page summarizes every sample program under `rex/examples`.

## Core Language

- `rex/examples/hello.rex`: Basic hello world + time measurement.
- `rex/examples/loops.rex`: `while`, range `for`, vector `for`, `break`, `continue`, slicing.
- `rex/examples/structs.rex`: Struct definition, methods with `impl`, field mutation.
- `rex/examples/enums.rex`: Enum variants and `match` usage.
- `rex/examples/simple_shadow.rex`: Simple variable shadowing behavior.
- `rex/examples/test_shadowing.rex`: Multiple shadowing scenarios.

## Language Feature Regression Samples

- `rex/examples/test_compound_assign.rex`: Compound assignment on variables and indexed values.
- `rex/examples/test_multi_match.rex`: Multi-tag `match` arms.
- `rex/examples/test_nested_assign.rex`: Nested member assignment, nested calls, and mixed index/member mutation.
- `rex/examples/test_struct_lit.rex`: Struct literals with named fields.
- `rex/examples/test_wildcard_match.rex`: Wildcard `match` arms with `_`.

## Error Handling and Flow

- `rex/examples/result.rex`: Handling `Result` with `match`.
- `rex/examples/try.rex`: Using `?` for error propagation.
- `rex/examples/defer.rex`: Scope cleanup with `defer`.

## Ownership and Bonds

- `rex/examples/ownership_thread_safe.rex`: Ownership debug tracing with spawned tasks.
- `rex/examples/bonds_test.rex`: Bond lifecycle coverage (`bond`, `commit`, `rollback`).
- `rex/examples/test_rollback_correct.rex`: Valid rollback flow.
- `rex/examples/test_rollback_error.rex`: Rollback edge case sample.

## Standard Library Modules

- `rex/examples/io.rex`: File and line I/O operations.
- `rex/examples/os_fs.rex`: OS info + filesystem checks and directory creation.
- `rex/examples/collections.rex`: Vector/map/set operations.
- `rex/examples/json.rex`: JSON encode/decode with typed and dynamic values.
- `rex/examples/time.rex`: Time APIs and elapsed calculations.
- `rex/examples/threads.rex`: Channels and message passing.
- `rex/examples/spawn.rex`: Basic spawn workers and wait.
- `rex/examples/memory.rex`: Pointer allocation, dereference, `box`, `drop`.

## Performance

- `rex/examples/benchmark.rex`: Numeric loop benchmark.
- `rex/examples/bench_vec.rex`: Vector push benchmark.
- `rex/examples/calculator_console.rex`: Console expression calculator with `math.eval`.

## UI and Games

- `rex/examples/xo.rex`: Tic-tac-toe with minimax AI and UI rendering.
- `rex/examples/dino/dino.rex`: Dino-style runner game using UI/audio/time/random.
- `rex/examples/flappy-bird/bird.rex`: Flappy Bird clone using UI/audio/images.

## Temporal

- `rex/examples/simple_temporal.rex`: Basic `within` temporal block usage.
