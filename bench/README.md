# itabench

Benchmark harness for live Hebrew/English caption engines. Always run it through `uv`:

```bash
uv run itabench --help
uv run pytest
```

## Working inside iCloud Drive

If this checkout lives in iCloud Drive, macOS keeps flagging the editable-install `.pth` file
in `.venv` as `hidden`, and Python 3.13 silently ignores hidden `.pth` files. The symptom is
`ModuleNotFoundError: No module named 'itabench'` from `uv run itabench`, which comes and goes.
Install the package non-editable instead; `cache-keys` in `pyproject.toml` rebuilds it
whenever `src/**/*.py` changes:

```bash
export UV_NO_EDITABLE=1   # add to your shell profile
```

pytest imports from `src/` directly (`pythonpath` in `pyproject.toml`), so tests work either way.
