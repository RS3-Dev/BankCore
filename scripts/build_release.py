"""Build the mod.io runtime ZIP with entry points at its root."""
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]


def build():
    manifest = json.loads((ROOT / "plugin.json").read_text(encoding="utf-8"))
    assert manifest["name"] == "Bank Core"
    assert manifest.get("contactEmailAddress")
    assert "description" not in manifest and "dependencies" not in manifest
    assert "requiredDependencies" in manifest
    license_text = (ROOT / "LICENSE").read_text(encoding="utf-8").strip()
    assert license_text in (ROOT / "main.lua").read_text(encoding="utf-8")
    files = [ROOT / "main.lua", ROOT / "plugin.json", *sorted((ROOT / "lib").rglob("*.lua"))]
    output = ROOT / "dist" / f"bankcore-{manifest['version']}-corrected.zip"
    output.parent.mkdir(exist_ok=True)
    with ZipFile(output, "w", ZIP_DEFLATED) as archive:
        for path in files:
            archive.write(path, path.relative_to(ROOT).as_posix())
    with ZipFile(output) as archive:
        assert archive.testzip() is None
        assert {"main.lua", "plugin.json"} <= set(archive.namelist())
        assert all(Path(name).suffix in (".lua", ".json") for name in archive.namelist())
    print(output)


if __name__ == "__main__":
    build()
