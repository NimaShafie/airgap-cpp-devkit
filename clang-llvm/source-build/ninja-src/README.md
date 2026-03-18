# ninja-src/ — Vendored Ninja Build System

### Author: Nima Shafie

This directory contains the Ninja build system source tarball.
Ninja dramatically reduces LLVM build time compared to `make`
(typically 2–3x faster) and significantly reduces peak RAM usage
during the link step.

## Contents

```
ninja-src/
├── ninja-1.13.2.tar.gz    ← Ninja source tarball (~220 KB, committed)
└── .gitignore              ← Ignores extracted source and build output
```

## When is Ninja built?

`build-clang-format.sh` checks whether Ninja is available on PATH.
If not found, it automatically builds Ninja from this tarball before
building clang-format. The compiled `ninja` binary is placed at:

- `bin/linux/ninja`         (Linux)
- `bin/windows/ninja.exe`   (Windows — only if not found in VS install)

## Source

Ninja 1.13.2 from: https://github.com/ninja-build/ninja/releases/tag/v1.13.2
SHA256: 6f98805688d19672bd699fbbfa2c2cf0fc054ac3df1f0e6a47664d963d530255  ninja-1.13.2.tar.gz

## Updating Ninja

On a connected machine, replace the tarball:
  curl -L -o ninja-src/ninja-1.13.2.tar.gz \
    https://github.com/ninja-build/ninja/releases/download/v1.13.2/ninja-1.13.2.tar.gz

Verify SHA256, then commit the updated tarball.
