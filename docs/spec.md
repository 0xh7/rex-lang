# Rex Language Spec (Current Implementation)

This document describes the implementation that exists in this repository today.
It follows compiler and runtime behavior first, and only states rules we can point to in code.

## 1. Design Direction

Rex aims to be:
- Simple to read and write
- Fast to compile
- Strong on correctness checks (types, ownership, borrows)
- Practical for systems-style tasks with a compact runtime

The current compiler pipeline is:

1. Lexer (tokenization)
2. Parser (AST construction)
3. Typechecker (types, ownership, bond rules)
4. C code generation
5. Native compilation with your C compiler

## 2. Program Structure

A Rex program is a list of items and statements.

Top-level items:
- `use` imports
- `fn` functions
- `struct` definitions
- `enum` definitions
- `impl` method blocks
- `type` aliases

Example:

```rex
use rex::io

struct Point { x: f64, y: f64 }

impl Point {
    fn len(&self) -> f64 {
        return sqrt(self.x * self.x + self.y * self.y)
    }
}

fn main() {
    let p = Point { x: 3, y: 4 }
    println(p.len())
}
```

## 3. Type System

Rex supports:
- Numeric types (all numeric names map to numeric behavior)
- `bool`, `str`, `nil`
- Struct and enum types
- Tuples
- References: `&T`, `&mut T`
- Pointers: `*T`
- Containers: `Vec<T>`, `Map<K, V>`, `Set<T>`
- Channels: `Sender<T>`, `Receiver<T>`
- `Result<T, E>` (with `E` defaulting to `str` when omitted)

Type annotations are optional in many places, but recommended at boundaries.

## 4. Ownership and Borrowing

Rex performs ownership checks in the typechecker:
- Non-copy values are moved on use
- Copy-like values can be reused
- Immutable and mutable borrows are tracked
- Invalid aliasing patterns are rejected
- Some reference lifetime mistakes are rejected (outliving checks)

The ownership model is documented in detail in `docs/ownership.md`.

## 5. Control Flow

Supported flow constructs:
- `if` / `else`
- `while`
- `for` range loops (`for i in a..b`)
- `for` over vectors (`for x in vec`)
- `match` for enums and `Result`
- `return`, `break`, `continue`
- `defer`

`match` arms support:
- a single tag, optionally with a binding (`Some(x) => ...`)
- multiple tags in one arm (`A | B => ...`)
- a wildcard fallback arm (`_ => ...`)

Assignment forms supported today include:
- direct assignment (`x = value`)
- compound assignment (`x += value`, etc.)
- member assignment (`obj.field = value`)
- index assignment (`v[i] = value`)
- nested mixed paths such as `items[0].value += 1`

Struct values can be created through either constructor calls (`Type.new(...)`)
or named-field literals (`Type { field: value }`).

## 6. Error Handling

Rex uses `Result` values and supports:
- `Ok(value)`
- `Err(error)`
- `expr?` to propagate errors

`?` is lowered into generated control flow that returns early on `Err`.

## 7. Bond System

Rex includes transaction-like scoped operations:
- `bond name = value`
- mutate state
- `commit` to keep changes
- `rollback` to undo tracked changes

Current rollback tracks and undoes:
- variable assignment
- struct member assignment
- index assignment

See `docs/bonds_system.md` for full details and examples.

## 8. Concurrency Model

Rex supports:
- `spawn { ... }`
- channel creation and message passing
- waiting for spawned work in runtime

Basic pattern:

```rex
use rex::thread as th

fn main() {
    let (tx, rx) = th.channel<i32>()
    spawn { tx.send(7) }
    println(rx.recv())
}
```

## 9. Runtime and Platform Notes

The generated C uses `rex/runtime_c`.

Platform notes:
- UI backend:
  - Windows: Win32
  - Linux: X11
  - macOS: Cocoa
- HTTPS:
  - Windows: WinHTTP
  - Linux/macOS: OpenSSL (`libssl`, `libcrypto`)

## 10. Stability Notes

Rex is actively maintained and used across the examples in this repository.
For upcoming goals and priorities, see `docs/roadmap.md`.
