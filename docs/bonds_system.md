# Rex Bond System

The bond system is Rex's scoped mutation log.
You enter a bond, perform writes, and then end that scope with either `commit` or `rollback`.

## 1. Core Syntax

```rex
bond x = 10
x = 20
commit
```

Or:

```rex
bond x = 10
x = 20
rollback
```

## 2. What Commit Does

`commit` finalizes changes performed while the bond is active.
No undo is applied.

## 3. What Rollback Does

`rollback` reverts tracked mutations recorded during the active bond.

Current rollback tracking covers:
- variable assignment (`a = ...`)
- struct member assignment (`obj.field = ...`)
- index assignment (`v[i] = ...`)

Compound assignment forms such as `+=`, `-=`, `*=`, `/=`, and `%=` are
tracked through the same assignment paths. This means operations like
`score += 1`, `player.hp += 10`, and `v[0] += 3` participate in rollback.

Rollback applies undo in reverse order (last change first).

## 4. Bond Variable After Rollback

After rollback, using the rolled-back bond variable is rejected by the checker.
Treat rollback as cancellation of that bond state.

## 5. Scope Safety Rules

You must close an active bond with `commit` or `rollback` before leaving scope.
Leaving scope with an active bond is reported as an error.

## 6. Move Restriction Inside Active Bond

When assigning inside an active bond, moving non-copy values through direct
identifier assignment is rejected by the typechecker.

This keeps rollback behavior predictable and avoids partially moved transactional state.

## 7. Examples

### Commit Example

```rex
fn commit_demo() {
    bond score = 0
    score += 10
    score += 10
    commit
    println("committed")
}
```

### Rollback Example

```rex
struct P { x: i32 }

fn rollback_demo() {
    mut p = P.new(1)
    bond t = 0
    p.x += 6
    rollback
    println(p.x) // back to 1
}
```

### Index Rollback Example

```rex
fn rollback_index() {
    mut v = [10, 20, 30]
    bond t = 0
    v[1] += 79
    rollback
    println(v[1]) // back to 20
}
```
