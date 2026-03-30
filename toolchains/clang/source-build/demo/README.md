# clang-tidy demo

### Author: Nima Shafie

Demonstrates `clang-tidy` against a C++ file with intentional issues.

---

## Usage

```bash
bash toolchains/clang-source-build/demo/run-demo.sh
```

`clang-tidy` must be assembled first:

```bash
bash toolchains/clang-source-build/setup.sh
```

---

## What it checks

| Check | Issue in demo.cpp |
|-------|------------------|
| `modernize-use-nullptr` | `NULL` macro used instead of `nullptr` |
| `modernize-use-override` | Virtual method override missing `override` keyword |
| `modernize-loop-convert` | Index-based loop convertible to range-for |
| `readability-magic-numbers` | Bare numeric literal passed directly to function |
| `cppcoreguidelines-init-variables` | Local variable declared but never initialized before use |
| `performance-unnecessary-copy-initialization` | `std::string` parameter passed by value instead of `const&` |

---

## Files

| File | Purpose |
|------|---------|
| `demo.cpp` | C++ file with one intentional issue per check category |
| `run-demo.sh` | Runs clang-tidy and prints diagnostics |

---

## Notes

- `run-demo.sh` never modifies `demo.cpp` -- it is read-only input.
- `clang-tidy` exits non-zero when it finds issues; the script captures and
  displays this output rather than treating it as a script failure.
- To apply fixes automatically (on a copy), use `--fix` and point at your own
  file -- do not pass `--fix` against `demo.cpp` as that would remove the
  intentional issues.