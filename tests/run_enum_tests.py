#!/usr/bin/env python3
"""Run enum regressions in an isolated Godot project using a built extension."""

import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, help="Godot executable")
    parser.add_argument("--library", required=True, type=Path, help="Built debug extension")
    args = parser.parse_args()
    library = args.library.resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="tree-sitter-gd-enums-") as directory:
        project = Path(directory)
        shutil.copy2(library, project / library.name)
        shutil.copy2(Path(__file__).with_name("test_enums.gd"), project / "test_enums.gd")
        (project / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="Enum regression tests"\n'
        )
        (project / "test.gdextension").write_text(
            '[configuration]\nentry_symbol="tree_sitter_gd_init"\n'
            'compatibility_minimum="4.1"\n[libraries]\n'
            f'debug="res://{library.name}"\n'
        )
        cache = project / ".godot"
        cache.mkdir()
        (cache / "extension_list.cfg").write_text("res://test.gdextension\n")
        result = subprocess.run(
            [args.godot, "--headless", "--path", str(project),
             "--log-file", str(project / "godot.log"), "--script", "res://test_enums.gd"],
            capture_output=True, text=True, timeout=60,
        )
        print(result.stdout, end="")
        print(result.stderr, end="")
        # Script parse errors may not cause Godot to return a nonzero exit code.
        if result.returncode or "PASS: unnamed enum regressions" not in result.stdout:
            raise SystemExit(result.returncode or 1)


if __name__ == "__main__":
    main()
