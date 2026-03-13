# Temporary Local Testing

This package includes a disposable `test-repo/` for local validation.

## No permanent global Git changes

Use either:

```bat
git config --local core.hooksPath tools/coding-standard/hooks
```

or a one-shot commit:

```bat
git -c core.hooksPath=tools/coding-standard/hooks commit -m "Test hook"
```

Both approaches avoid modifying global Git configuration.
