# Getting Started with Rex

Quick setup reference for running a first Rex program.

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

Source checkout usage:

```bash
cd rex
lua compiler/cli/rex.lua init my-app
```

## 7. Build and Run Your Own File

Installed Rex build:

```bash
rex build my-app/src/main.rex
```

Direct run:

```bash
rex run my-app/src/main.rex
```

Source checkout usage:

```bash
cd rex
lua compiler/cli/rex.lua build my-app/src/main.rex
lua compiler/cli/rex.lua run my-app/src/main.rex
```

## 8. Common Commands

- Format source:
  - `rex fmt path/to/file.rex`
- Lint (same validation pipeline used in check):
  - `rex lint path/to/file.rex`
- Build all examples to generated C:
  - `rex test`

## 9. Further Reading

- Syntax: `docs/syntax.md`
- Ownership: `docs/ownership.md`
- Standard library: `docs/stdlib.md`
- Full command list: `docs/cli-reference.md`
- Common errors and fixes: `docs/troubleshooting.md`
