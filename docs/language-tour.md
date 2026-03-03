# Rex Language Tour

This is a practical tour of Rex features, from basic syntax to ownership and error handling.

## 1. Variables and Functions

```rex
fn add(a: i32, b: i32) -> i32 {
    return a + b
}

fn main() {
    let x = 10
    mut y = 20
    y += 1
    println(add(x, y))
}
```

What to notice:
- `let` is immutable by default.
- `mut` enables reassignment.
- Function return type uses `->`.

## 2. Structs and Methods

```rex
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

You can construct structs with either `Type.new(...)` or a named-field literal.

## 3. Enums and Match

```rex
enum State { Idle, Busy, Done(i32), Fail }

fn show(v: State) {
    match v {
        Idle | Busy => println("waiting"),
        Done(x) => println("value = " + x),
        _ => println("fallback"),
    }
}
```

`match` supports single-tag bindings, multi-tag arms, and wildcard fallback arms.

## 4. Result and `?`

```rex
use rex::io

fn read_text(path: str) -> Result<str> {
    let data = io.read_file(&path)?
    return Ok(data)
}
```

`?` returns early with `Err` if the call fails.

## 5. Ownership and Borrowing

```rex
fn main() {
    mut n = 10
    let r = &mut n
    *r = 20
    println(n)
}
```

Rules you will feel quickly:
- You cannot mutate while conflicting borrows are active.
- Non-copy values can be moved; moved values cannot be reused.
- Nested writes such as `obj.inner.value += 1` follow the same ownership rules.

## 6. Defer

```rex
fn main() {
    let v = [1, 2, 3]
    defer {
        drop(v)
    }
    println("work done")
}
```

`defer` runs at scope exit and is useful for cleanup.

## 7. Bond / Commit / Rollback

```rex
fn main() {
    mut x = 1
    bond t = 0
    x = 9
    rollback
    println(x) // back to 1
}
```

Use bonds when you want controlled, reversible updates.

## 8. Concurrency with Spawn + Channel

```rex
use rex::thread as th

fn main() {
    let (tx, rx) = th.channel<i32>()
    spawn { tx.send(7) }
    println(rx.recv())
}
```

## 9. Standard Modules

Rex includes practical modules for daily work:
- `io`, `fs`, `os`, `path`
- `collections`, `json`, `http`, `net`
- `thread`, `time`, `random`
- `ui`, `audio`, `log`

See full list: `docs/stdlib.md`.
