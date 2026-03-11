# Rex Troubleshooting: Common Errors

This file is a working error guide for the current compiler and runtime.
Each section includes:
- the actual error message
- what it means
- how to fix it quickly

## 1. Parser and Lexer Errors

### `Parse error at line:col: Expected 'X', got 'Y'`
Meaning:
- The parser expected a specific token and found something else.

Common causes:
- Missing `)` / `}` / `]`
- Typo in keyword or symbol
- Wrong statement shape

How to fix:
- Check the exact line and the previous line.
- Verify matching brackets first.

### `Parse error ...: Unexpected token: ...`
Meaning:
- The token does not fit the current grammar position.

How to fix:
- Make sure the construct is valid in that context (top-level vs inside a block).

One common case is assignment to a shape the current statement parser does not
accept. Check the full left-hand side and make sure it is a valid binding,
member path, or index/member chain.

### `Unterminated string at line:col`
Meaning:
- String started with `"` but was not closed.

How to fix:
- Add the closing `"`.
- If needed, escape quotes inside strings.

### `Unterminated block comment at line:col`
Meaning:
- A `/* ...` comment was never closed with `*/`.

How to fix:
- Close the comment block.

### `Parse error ...: Unterminated block`
Meaning:
- A `{` block was opened and not closed.

How to fix:
- Add the missing `}`.

### `Parse error ...: Slice assignment is not supported`
Meaning:
- Assignment to a slice range is not implemented.

Bad:
```rex
v[0..2] = other
```

Fix:
- Assign individual indices or replace the full value with another approach.

### `Parse error ...: pub can only be used on items`
Meaning:
- `pub` was used on a statement instead of top-level item.

Fix:
- Use `pub` only with items like `fn`, `struct`, `enum`, etc.

### `Parse error ...: Wildcard '_' must be the last arm in a match expression`
Meaning:
- A wildcard arm appeared before later arms in `match`.

Fix:
- Move `_ => ...` to the last arm.

## 2. Type and Name Errors

### `Unknown identifier: name`
Meaning:
- Variable/function not found in scope.

How to fix:
- Check spelling.
- Check scope lifetime.
- Confirm import exists (`use ...`).

### `Unknown type: TypeName`
Meaning:
- Type is not built-in and not declared.

How to fix:
- Define the type first or correct the type name.

### `Unknown function: name`
Meaning:
- Called function is not known in current context.

How to fix:
- Define it.
- Import module with `use`.
- Check if it is a module call (`io.read_file`) not a plain call.

### `Type arguments provided for non-generic function`
Meaning:
- You passed `<...>` to a function that is not generic.

Fix:
- Remove type arguments or call the correct generic function.

### `Expected N argument(s), got M`
Meaning:
- Wrong number of function arguments.

Fix:
- Match the function signature exactly.

### `Cannot infer type parameter T; provide explicit type arguments`
Meaning:
- Inference could not determine generic type(s).

Fix:
- Provide explicit type args:

```rex
let v = json.decode<any>(&raw)
```

## 3. Ownership and Borrow Errors

### `[E0601] name was moved`
Meaning:
- You used a value after move.

How to fix:
- Borrow instead of moving (`&name` / `&mut name`) where appropriate.
- Restructure flow so moved value is not reused.

### `[E0602] Cannot move x while it is mutably borrowed`
### `[E0603] Cannot move x while it is borrowed`
Meaning:
- A value cannot be moved while active borrows still point to it.

How to fix:
- End the borrow before transfer.
- Prefer another borrow if you only need read access.

### `[E0604] Cannot take &mut of immutable x`
Meaning:
- Mutable borrow requires a mutable binding.

How to fix:
- Declare the binding with `mut`.
- If mutation is not needed, use `&x`.

### `[E0605] Cannot take &mut x while borrowed`
Meaning:
- Mutable borrow conflicts with existing borrow.

Fix:
- End the other borrow first.
- Keep borrow scopes shorter.

### `[E0606] Cannot take &x while mutably borrowed`
Meaning:
- Immutable borrow conflicts with active mutable borrow.

Fix:
- Do not alias immutable and mutable access at the same time.

### `Cannot assign to immutable variable: x`
Meaning:
- Attempted reassignment of `let` binding.

Fix:
- Use `mut x = ...` if reassignment is intended.

### `Cannot assign to field of immutable variable: x`
### `Cannot assign to index of immutable variable: x`
Meaning:
- A nested member or indexed assignment starts from an immutable root binding.

Fix:
- Mark the root binding as `mut`.

### `[E0607] Cannot assign to x while it is borrowed`
Meaning:
- Value is currently borrowed; mutation is blocked by safety rules.

Fix:
- Move mutation outside borrow scope.

### `[E0608] argument N expects &T; use &`
Meaning:
- A function expected a borrowed argument but a value was passed directly.

Fix:
- Pass `&value` or `&mut value` to match the parameter.

### `[E0701] cannot move value inside active bond (only Copy types allowed)`
Meaning:
- Active bond state only permits copy-like transfers.

Fix:
- Keep non-Copy moves outside the active bond.
- Rewrite the bond body to mutate copy-compatible state only.

## 4. Result / Try Errors

### `Operator ? expects Result`
Meaning:
- `?` is used on non-`Result` value.

Fix:
- Only use `?` with expressions returning `Result<...>`.

### `Operator ? requires function to return Result`
Meaning:
- Current function does not return `Result`, so error propagation is invalid.

Fix:
- Change function return type to `Result<...>` or handle error manually.

## 5. Match Errors

### `match expects enum or Result`
Meaning:
- `match` currently works on enum/result-style tagged values.

Fix:
- Match only supported tagged values.

### `Unknown match arm tag: TagName`
Meaning:
- Arm tag does not exist on that enum/result.

Fix:
- Use valid variant/tag names.

### `Duplicate match arm tag: TagName`
Meaning:
- Same arm tag appears more than once.

Fix:
- Keep one arm per tag.

### Runtime panic: `non-exhaustive match`
Meaning:
- Generated runtime hit a missing arm.

Fix:
- Add all missing variants/tags.

## 6. Bond Errors

### `commit outside of bond`
### `rollback outside of bond`
Meaning:
- `commit`/`rollback` was used without active `bond`.

Fix:
- Use them only after `bond name = value`.

### `cannot exit scope with active bond (commit or rollback required)`
Meaning:
- Flow leaves scope with bond still open (including `return`, `break`, `continue`).

Fix:
- Always close bond before leaving scope.

### `use of rolled-back bond variable 'x'`
Meaning:
- Rolled-back bond variable is considered invalid for later use.

Fix:
- Rebind a fresh variable after rollback if needed.

### `cannot move value inside active bond (only Copy types allowed)`
Meaning:
- Active bond assignment attempted to move non-copy value.

Fix:
- Avoid moves inside bond assignments.
- Use copy-like values or redesign operation boundaries.

### Codegen error: `Bond 'x' left scope without commit/rollback`
Meaning:
- Generated code detected an unclosed bond.

Fix:
- Add explicit `commit` or `rollback` in every control path.

## 7. Struct/Enum Errors

### `Unknown field: f on Type`
Meaning:
- Accessing or assigning a field that does not exist.

Fix:
- Correct field name or type.

### `Unknown field 'f' on struct Type`
### `Duplicate field 'f' in struct literal Type`
### `Missing field 'f' in struct literal Type`
Meaning:
- A struct literal uses a wrong field name, repeats a field, or leaves one out.

Fix:
- Use each declared field exactly once.
- Match the struct definition by name.

### `Constructor expects N argument(s), got M`
Meaning:
- `Type.new(...)` got wrong arg count.

Fix:
- Match struct field order/count.

### `Unknown enum variant: Enum.V`
Meaning:
- Variant name does not exist.

Fix:
- Use a defined variant exactly.

### `Enum variant Enum.V requires payload`
Meaning:
- Variant needs payload but was used without args.

Fix:
- Pass payload value(s) as required.

## 8. For Loop Errors

### `for-in expects vector`
Meaning:
- `for x in y` currently expects vector-like iterable.

Fix:
- Iterate over vectors, or adapt value before looping.

### Runtime panic: `for range expects numbers`
Meaning:
- Range bounds were not numeric at runtime.

Fix:
- Ensure both bounds in `a..b` are numeric.

## 9. CLI and Build Errors

### `Include cycle detected: ...`
Meaning:
- `// @include` chain references itself.

Fix:
- Break the cycle and keep include graph acyclic.

### `C compile failed. Check that your compiler is available.`
Meaning:
- Native compilation failed.

Fix:
- Install/verify C compiler.
- Check platform dependencies (e.g., OpenSSL dev libs for some features).

### `Invalid build mode: ... (expected 'release' or 'debug')`
Fix:
- Use only `--mode release` or `--mode debug`.

### `--out requires a value` (and similar CLI option errors)
Fix:
- Provide option value right after the flag.

## 10. Practical Debug Flow

When a file fails to build, use this order:

1. `lua compiler/cli/rex.lua check your_file.rex`
2. Fix parser/type errors from top to bottom.
3. Re-run `check`.
4. Then run:
   `lua compiler/cli/rex.lua build your_file.rex`
5. If needed, run:
   `lua compiler/cli/rex.lua run your_file.rex`

This usually resolves issues faster than jumping straight to runtime execution.
