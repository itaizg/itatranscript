from pathlib import Path

from itabench.results_store import ResultsStore


def test_rewrite_leaves_one_file_with_second_content(tmp_path: Path) -> None:
    store = ResultsStore(tmp_path)
    store.write("e", "none", "on", "c1", "json", "first")
    target = store.write("e", "none", "on", "c1", "json", "second")
    assert target.read_text() == "second"
    assert [p.name for p in target.parent.iterdir()] == ["c1.json"]
    assert store.files("json") == [target]
