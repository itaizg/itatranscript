"""Command-line entry point for the benchmark harness."""

import typer

app = typer.Typer(help="Benchmark live caption engines.")


@app.callback()
def main() -> None:
    """Benchmark live caption engines."""
