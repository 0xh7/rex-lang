# Rex Roadmap

This roadmap is focused on practical milestones for the next stages of the language.

## 1. Language and Compiler

### Short Term
- Tighten diagnostics (clearer error messages with better context).
- Expand parser/typechecker tests for edge cases.
- Continue polishing mixed lvalue parsing and assignment coverage.
- Improve generic type inference in complex call chains.

### Mid Term
- Add clearer module/package story.
- Improve type system ergonomics for large projects.
- Add stronger static guarantees around advanced features.

### Long Term
- Evaluate additional backends and compile pipeline improvements.
- Provide performance and memory profiling workflows for Rex programs.

## 2. Standard Library and Runtime

### Short Term
- Continue hardening `io`, `fs`, `json`, `http`, `collections`.
- Add more runtime-level tests for platform-specific functionality.

### Mid Term
- Improve consistency across modules (naming, signatures, error behavior).
- Expand utility coverage for real-world application scaffolding.

### Long Term
- Add deeper observability and debugging facilities in runtime.
- Improve packaging/distribution flow for larger apps.

## 3. Tooling

### Short Term
- Improve VS Code extension polish (syntax highlighting, language behaviors).
- Provide cleaner generated build artifacts and paths.

### Mid Term
- Add richer language tooling hooks (navigation, diagnostics integration).
- Improve installer and release automation.

### Long Term
- Build a full developer workflow around project templates, testing, and release.

## 4. Documentation

### Short Term
- Keep docs aligned with implemented behavior after each major change.
- Keep syntax guides current as language features such as struct literals,
  compound assignment, and richer `match` arms expand.
- Expand guides with more end-to-end examples.

### Mid Term
- Add dedicated migration notes when syntax or semantics evolve.
- Publish language patterns and best practices.

### Long Term
- Provide a full handbook structure for application-scale development.
