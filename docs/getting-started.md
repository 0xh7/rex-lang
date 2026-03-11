# Getting Started with Rex

Use this file when you want the shortest path from a fresh checkout to a running Rex program.

## 1. Prerequisites

Install:
- Lua 5.4+ (or compatible runtime)
- A C compiler (`cc`, `clang`, or `gcc`)

Available installation flows:

## 2. Run Rex from Installer (Windows)

Windows installer usage:

```powershell
rex run "C:\rex-lang\rex\examples\hello.rex"
```

PowerShell fallback:

```powershell
& "C:\Program Files\RexLang\bin\rex.cmd" run "C:\rex-lang\rex\examples\hello.rex"
```

Windows compiler setup (when `C compiler not found` appears):

```powershell
winget install -e --id LLVM.LLVM
setx CC clang
```

## 3. Run Rex from Source Repository

From the repo root:

```bash
cd rex
lua compiler/cli/rex.lua run examples/hello.rex
```

Expected output:
- `Hello from Rex`
- elapsed time in milliseconds

## 4. Check a File (Types + Ownership)

Validation:

```bash
rex check "C:\rex-lang\rex\examples\hello.rex"
```

Source checkout usage:

```bash
cd rex
lua compiler/cli/rex.lua check examples/hello.rex
```

Successful validation prints `OK ...`.

## 5. Try the Newer Syntax Samples

Current syntax samples:

```bash
rex run "C:\rex-lang\rex\examples\test_struct_lit.rex"
rex run "C:\rex-lang\rex\examples\test_nested_assign.rex"
rex run "C:\rex-lang\rex\examples\test_multi_match.rex"
```

Source checkout usage:

```bash
cd rex
lua compiler/cli/rex.lua run examples/test_struct_lit.rex
lua compiler/cli/rex.lua run examples/test_nested_assign.rex
lua compiler/cli/rex.lua run examples/test_multi_match.rex
```

## 6. Create a New Project

Project initialization:

```bash
rex init my-app
```

Generated files:
- `my-app/rex.toml`
- `my-app/src/main.rex`

Generated manifest:
- `entry = "src/main.rex"`

Source checkout usage:

```bash
cd rex
lua compiler/cli/rex.lua init my-app
```

## 7. Build and Run Your Own File

Installed Rex build:

```bash
cd my-app
rex build
```

Direct run:

```bash
cd my-app
rex run
```

Source checkout usage:

```bash
cd rex/my-app
lua ../compiler/cli/rex.lua build
lua ../compiler/cli/rex.lua run
```

All of these commands resolve the default program from `entry` in `rex.toml`.

## 8. Common Commands

- Format source:
  - `rex fmt path/to/file.rex`
- Lint (same validation pipeline used in check):
  - `rex lint path/to/file.rex`
- Build all examples to generated C:
  - `rex test`
- Add a local path dependency to the manifest:
  - `rex add utils --path ../utils`
- Add a git dependency to the manifest:
  - `rex add jsonx --git https://github.com/example/jsonx --rev 4e2d9f1`
- Remove a manifest dependency:
  - `rex remove utils`

## 9. Next Step: Manifest-Aware Projects

Once `rex.toml` exists, these commands default to the manifest entry:

```bash
cd my-app
rex build
rex run
rex check
```

For local dependencies:

```bash
rex add utils --path ../utils
rex deps
rex install
```

For git-pinned dependencies:

```bash
rex add jsonx --git https://github.com/example/jsonx --rev 4e2d9f1
rex deps
rex install
```

This updates `rex.toml`, validates dependency manifests, fetches git dependencies into cache, and writes `rex.lock`.

Minimal dependency import:

```rex
use utils as u

fn main() {
    u.hello()
}
```

Imported package surface today:
- `pub fn` via `pkg.fn()`
- `pub struct` via `pkg.Type.new(...)`
- `pub enum` via `pkg.Enum.Variant(...)`
- `pub type` in signatures via `pkg::Alias`

Example:

```rex
use geom as g

fn take_point(p: g::Point) -> i32 {
    return p.len()
}

fn main() {
    let p = g.Point.new(3, 4)
    println(take_point(p))
}
```

Current limitation:
- imported struct literals are not package-qualified yet; use constructors

## 10. Further Reading

- Syntax: `docs/syntax.md`
- Ownership: `docs/ownership.md`
- Standard library: `docs/stdlib.md`
- Full command list: `docs/cli-reference.md`
- Common errors and fixes: `docs/troubleshooting.md`
