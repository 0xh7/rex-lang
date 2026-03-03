# Rex Ownership and Borrowing

Rex uses ownership checks to catch common memory and aliasing mistakes before codegen.
This document explains the behavior implemented today.

## 1. Ownership Basics

Each value has one logical owner.
When a non-copy value is used by value, it is considered moved and can no longer be used.

Example:

```rex
fn main() {
    let v = [1, 2, 3]
    drop(v)      // consumes v
    // println(v) // ownership error: moved
}
```

## 2. Copy-like Values

The checker treats these as copy-like:
- numbers
- booleans
- `nil`
- immutable references (`&T`)
- tuples composed only of copy-like values

Copy-like values can be reused after reads.

## 3. Borrowing

### Immutable borrow (`&`)

```rex
let name = "rex"
let r = &name
println(*r)
```

### Mutable borrow (`&mut`)

```rex
mut n = 10
let r = &mut n
*r = 20
println(n)
```

Rules enforced:
- You cannot take `&mut` while the value is already borrowed.
- You cannot take `&` while the value is mutably borrowed.
- You cannot move a value while it is borrowed.

## 4. Reassignment and Borrow Safety

Reassigning a borrowed variable is rejected:

```rex
mut x = 1
let r = &x
// x = 2  // rejected while borrowed
println(*r)
```

The same rule applies to nested mutation paths. The checker uses the root binding
for safety checks, so member and index mutation are blocked while the owner is
borrowed.

```rex
struct Counter { value: i32 }

fn main() {
    mut items = [Counter.new(1)]
    let r = &items
    // items[0].value += 1  // rejected while borrowed
    println("borrowed")
}
```

For references, Rex tracks source and destination when references are reassigned.

## 5. Lifetimes (Current Checks)

Rex performs a practical lifetime check for references:
- A reference should not outlive the value it points to.

The checker reports cases where a reference escapes the scope of its target.

## 6. Defer and Ownership

`defer` is ownership-aware in the checker:
- Deferred expressions are checked in defer mode.
- Borrow/move uses are tracked and applied back to the main flow.

Example:

```rex
fn main() {
    let v = [1, 2, 3]
    defer {
        drop(v)
    }
}
```

## 7. Ownership Debug Mode

Rex supports a debug statement for ownership tracing:

```rex
debug ownership {
    trace: x
    check: x
}
```

This is useful for development and diagnostics, especially when validating
ownership-heavy code.

## 8. Practical Advice

- Prefer clear scopes and short-lived mutable borrows.
- Use immutable borrows by default.
- Move values intentionally; do not rely on accidental reuse.
- Use `defer` for explicit cleanup paths.
