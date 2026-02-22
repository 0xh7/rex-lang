# Getting Started with Rex

This guide gets you from zero to running your first Rex program in a few minutes.

## 1. Prerequisites

Install:
- Lua 5.4+ (or compatible runtime)
- A C compiler (`cc`, `clang`, or `gcc`)

Then pick one of the flows below.

## 2. Run Rex from Installer (Windows)

If you installed Rex from the Windows setup package, run:

```powershell
rex run "C:\rex-lang\rex\examples\hello.rex"
```

If `rex` is not recognized in PowerShell, open a new terminal window or use:

```powershell
& "C:\Program Files\RexLang\bin\rex.cmd" run "C:\rex-lang\rex\examples\hello.rex"
```

If you see `C compiler not found`, install Clang and set it as default:

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

You should see output similar to:
- `Hello from Rex`
- elapsed time in milliseconds

## 4. Check a File (Types + Ownership)

Before running a program, use `check`:

```bash
rex check "C:\rex-lang\rex\examples\hello.rex"
```

From source checkout:

```bash
cd rex
lua compiler/cli/rex.lua check examples/hello.rex
```

If everything is valid, the command prints `OK ...`.

## 5. Create a New Project

Initialize a project folder:

```bash
rex init my-app
```

This creates:
- `my-app/rex.toml`
- `my-app/src/main.rex`

From source checkout:

```bash
cd rex
lua compiler/cli/rex.lua init my-app
```

## 6. Build and Run Your Own File

Build to C and native binary (installed Rex):

```bash
rex build my-app/src/main.rex
```

Run directly:

```bash
rex run my-app/src/main.rex
```

From source checkout:

```bash
cd rex
lua compiler/cli/rex.lua build my-app/src/main.rex
lua compiler/cli/rex.lua run my-app/src/main.rex
```

## 7. Useful Daily Commands

- Format source:
  - `rex fmt path/to/file.rex`
- Lint (same validation pipeline used in check):
  - `rex lint path/to/file.rex`
- Build all examples to generated C:
  - `rex test`

## 8. Where to Go Next

- Syntax: `docs/syntax.md`
- Ownership: `docs/ownership.md`
- Standard library: `docs/stdlib.md`
- Full command list: `docs/cli-reference.md`
- Common errors and fixes: `docs/troubleshooting.md`
