# VS Code Extensions -- Air-Gap Package

Pre-downloaded VS Code extensions for offline installation on air-gapped Windows and Linux systems.

## Included Extensions

| Extension | Publisher | Version | Platform |
|-----------|-----------|---------|----------|
| C/C++ Extension Pack | Microsoft | 1.5.1 | Universal |
| C/C++ | Microsoft | 1.30.4 | win32-x64, linux-x64 |
| C++ TestMate | Mate Pek | 4.22.3 | Universal |
| Python | Microsoft | 2026.5.2026031201 | win32-x64, linux-x64 |

## Automated Installation (Recommended)

Requires VS Code to be installed and `code` on PATH.

```bash
# Verify, reassemble, and install all extensions for your platform
bash dev-tools/dev-tools/vscode-extensions/setup.sh

# Verify SHA256 only (no install)
bash dev-tools/dev-tools/vscode-extensions/setup.sh --verify

# Dry run -- show what would be installed without installing
bash dev-tools/dev-tools/vscode-extensions/setup.sh --dry-run
```

## Manual Installation

If the automated script doesn't work, install extensions manually via VS Code UI:

1. Open VS Code
2. Open the Extensions view (`Ctrl+Shift+X`)
3. Click the `...` menu (top-right of Extensions panel)
4. Select **Install from VSIX...**
5. Navigate to `dev-tools/dev-tools/vscode-extensions/vendor/` and select the `.vsix` file

Or via command line:
```bash
code --install-extension dev-tools/dev-tools/vscode-extensions/vendor/ms-vscode.cpptools-extension-pack-1.5.1.vsix
code --install-extension dev-tools/dev-tools/vscode-extensions/vendor/ms-vscode.cpptools-1.30.4-win32-x64.vsix   # Windows
code --install-extension dev-tools/dev-tools/vscode-extensions/vendor/ms-vscode.cpptools-1.30.4-linux-x64.vsix   # Linux
code --install-extension dev-tools/dev-tools/vscode-extensions/vendor/matepek.vscode-catch2-test-adapter-4.22.3.vsix
code --install-extension dev-tools/dev-tools/vscode-extensions/vendor/ms-python.python-2026.5.2026031201-win32-x64.vsix  # Windows
code --install-extension dev-tools/dev-tools/vscode-extensions/vendor/ms-python.python-2026.5.2026031201-linux-x64.vsix  # Linux
```

## Reassembling Split Extensions

The `ms-vscode.cpptools` extension is too large for a single file and is split into parts.
The `setup.sh` script handles reassembly automatically. To do it manually:

```bash
# Windows (win32-x64) -- 2 parts
cat dev-tools/dev-tools/vscode-extensions/vendor/ms-vscode.cpptools-1.30.4-win32-x64.vsix.part-{aa,ab} \
    > dev-tools/dev-tools/vscode-extensions/vendor/ms-vscode.cpptools-1.30.4-win32-x64.vsix

# Linux (linux-x64) -- 3 parts
cat dev-tools/dev-tools/vscode-extensions/vendor/ms-vscode.cpptools-1.30.4-linux-x64.vsix.part-{aa,ab,ac} \
    > dev-tools/dev-tools/vscode-extensions/vendor/ms-vscode.cpptools-1.30.4-linux-x64.vsix
```

## Adding Code to PATH (Windows)

If `code` is not recognized in Git Bash:

1. Open VS Code
2. Press `Ctrl+Shift+P` to open the Command Palette
3. Type **Shell Command: Install 'code' command in PATH**
4. Press Enter, then restart your terminal

## Updating Extensions

To update to newer versions:

1. Download the new `.vsix` files from the Marketplace (on a networked machine)
2. Replace the files in `vendor/`
3. Update the SHA256 hashes in `manifest.json`
4. Re-run `setup.sh`

Download URL pattern:
```
# Universal
https://marketplace.visualstudio.com/_apis/public/gallery/publishers/<publisher>/vsextensions/<extension>/<version>/vspackage

# Platform-specific
https://marketplace.visualstudio.com/_apis/public/gallery/publishers/<publisher>/vsextensions/<extension>/<version>/vspackage?targetPlatform=<platform>
```