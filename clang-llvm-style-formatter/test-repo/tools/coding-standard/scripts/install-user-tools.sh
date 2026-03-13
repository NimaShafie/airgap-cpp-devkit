#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
  echo "ERROR: This script must be run inside a Git repository."
  exit 1
fi
cd "$REPO_ROOT"
USER_BIN="$HOME/.local/cpp-coding-standard/llvm/bin"
VENDOR_BIN="$REPO_ROOT/tools/coding-standard/vendor/linux/llvm/bin"
ensure_tool() {
  tool_cmd="$1"
  if command -v "$tool_cmd" >/dev/null 2>&1; then
    echo "OK: $tool_cmd already available on PATH."
    return 0
  fi
  echo "$tool_cmd not found on PATH."
  if [ ! -x "$VENDOR_BIN/$tool_cmd" ]; then
    if [ "$tool_cmd" = "clang-format" ]; then
      echo "ERROR: $tool_cmd is required but no bundled portable binary was found."
      return 1
    else
      echo "WARNING: $tool_cmd is optional and no bundled portable binary was found."
      return 0
    fi
  fi
  mkdir -p "$USER_BIN"
  cp "$VENDOR_BIN/$tool_cmd" "$USER_BIN/$tool_cmd"
  chmod +x "$USER_BIN/$tool_cmd"
  case ":$PATH:" in
    *":$USER_BIN:"*) ;;
    *) export PATH="$USER_BIN:$PATH" ;;
  esac
  echo "Installed $tool_cmd to $USER_BIN"
  echo "Add this path to your shell profile if needed: $USER_BIN"
}
ensure_tool clang-format
ensure_tool clang-tidy || true
