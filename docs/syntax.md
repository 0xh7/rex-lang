# Rex Syntax Guide

Reference for syntax implemented by the current compiler.

## 1. Basic Rules

- Statements usually appear one per line.
- A trailing `;` is accepted in many statement forms, but not required everywhere.
- Comments:
  - Line comment: `// ...`
  - Block comment: `/* ... */`

## 2. Imports

Use module imports at top level:

```rex
use rex::io
use rex::thread as th
```

## 3. Top-Level Declarations

### Functions

```rex
fn add(a: i32, b: i32) -> i32 {
    return a + b
}
```

### Structs and Methods

```rex
struct User { name: str, age: i32 }

impl User {
    fn is_adult(&self) -> bool {
        return self.age >= 18
    }
}
```

### Enums

```rex
enum Option { Some(i32), None }
```

### Type Aliases

```rex
type Vec2 = Point;
```

## 4. Variables and Assignment

Immutable and mutable bindings:

```rex
let x = 10
mut y = 20
y = y + 1
```

Tuple destructuring:

```rex
let (tx, rx) = channel<i32>()
```

Member and index assignment:

```rex
p.x = 42
v[1] = 99
```

Compound assignment is supported for variables, member paths, and indexed paths:

```rex
count += 1
player.hp -= 10
items[0].value += 1
```

## 5. Expressions

Primary expressions:
- Numbers, strings, booleans, `nil`
- Identifiers
- Arrays: `[1, 2, 3]`
- Struct literals: `Point { x: 3, y: 4 }`
- Grouping: `(expr)`
- Member access: `obj.field`
- Calls: `f(a, b)`
- Indexing: `v[i]`
- Slicing: `v[a..b]`

Unary operators:
- `-expr`
- `!expr`
- `&expr`
- `&mut expr`
- `*expr`

Binary operators (current precedence high to low):
1. `* / %`
2. `+ -`
3. `< <= > >=`
4. `== !=`
5. `&&`
6. `||`

Try operator:

```rex
let text = io.read_file(&path)?
```

## 6. Control Flow

### If / Else

```rex
if n > 0 {
    println("positive")
} else {
    println("zero or negative")
}
```

### While

```rex
while running {
    work()
}
```

### For

Range loop:

```rex
for i in 0..10 {
    println(i)
}
```

Vector loop:

```rex
for item in values {
    println(item)
}
```

### Match

```rex
match value {
    Done(x) => println(x),
    Idle | Busy => println("waiting"),
    _ => println("fallback"),
}
```

`match` arms can use block bodies or expression-style bodies.
Bindings are supported on a single concrete tag arm such as `Some(x) => ...`.

## 7. Advanced Statements

### Defer

```rex
defer {
    println("cleanup")
}
```

### Spawn

```rex
spawn {
    do_work()
}
```

### Unsafe

```rex
unsafe {
    risky_call()
}
```

### Bonds

```rex
bond txn = 0
state = 10
rollback
```

### Temporal / Debug Ownership

```rex
within 5000 {
    println("inside temporal block")
}

debug ownership {
    trace: x
    check: x
}
```

## 8. Include Preprocessing

The CLI supports include expansion using comments:

```rex
// @include "path/to/file.rex"
```

Includes are resolved before lexing/parsing and detect include cycles.
