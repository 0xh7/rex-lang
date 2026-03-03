# Rex Programming Language

Rex is a systems-style language inspired by C/C++, Rust, and Go.
The compiler front-end is written in Lua and currently targets C through a small runtime.

The repository includes real working examples for structs, enums, generics,
ownership checks, concurrency, JSON, UI helpers, and more.

## Quick Start

Prerequisites:
- Lua 5.4+ (or compatible Lua runtime)
- A C compiler (`cc`, `clang`, or `gcc`)

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

Source checkout usage:

```bash
cd rex
lua compiler/cli/rex.lua run examples/hello.rex
```

Check types and ownership rules:

```bash
cd rex
lua compiler/cli/rex.lua check examples/hello.rex
```

Build all examples to generated C:

```bash
cd rex
lua compiler/cli/rex.lua test
```

## Language Highlights

- Structs, enums, methods (`impl`), and type aliases
- Generic functions and generic types
- `Result` + `?` operator for error propagation
- Ownership and borrow checking (`&` and `&mut`)
- `defer` for scope-based cleanup
- Transaction-like `bond / commit / rollback`
- Concurrency primitives (`spawn`, channels)
- Cross-platform runtime modules (`io`, `fs`, `time`, `json`, `http`, `ui`, and more)

## Documentation

- Language overview: `docs/spec.md`
- Syntax guide: `docs/syntax.md`
- Ownership model: `docs/ownership.md`
- Bond system: `docs/bonds_system.md`
- Standard library guide: `docs/stdlib.md`
- Common errors and fixes: `docs/troubleshooting.md`
- Getting started: `docs/getting-started.md`
- Language tour: `docs/language-tour.md`
- CLI reference: `docs/cli-reference.md`
- Examples index: `docs/examples-index.md`
- Roadmap: `docs/roadmap.md`

## Releases

GitHub releases are automated through `.github/workflows/release.yml`.
Each release publishes:

- `rex-<version>-windows-setup.exe`
- `rex-<version>-windows-portable.zip`

## Project Layout

- `rex/compiler` - lexer, parser, typechecker, and C code generator
- `rex/runtime_c` - C runtime used by generated programs
- `rex/examples` - sample Rex programs
- `docs` - language documentation
