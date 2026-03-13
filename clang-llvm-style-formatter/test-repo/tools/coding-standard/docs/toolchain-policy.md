# Toolchain Policy

## Supported versions

- Preferred LLVM/Clang version: 18.x
- Supported minimum: 17.x
- Unsupported: older than 17.x

## Required tools

- clang-format
- Python 3

## Optional but recommended

- clang-tidy
- compile_commands.json for each product build

## Non-admin policy

- No system PATH changes
- No machine-wide installation
- No global Git configuration
- User-path install only when bundled portable tools are present
