Drop portable Windows LLVM binaries here for non-admin user-scope install.

Expected files if you want setup to auto-install when missing:
- clang-format.exe
- clang-tidy.exe

The install script copies them to:
%LOCALAPPDATA%\cpp-coding-standard\llvmin
and updates the current user's PATH only.
