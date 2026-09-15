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
    parser.add_argument("--suite", default="test_enums.gd", choices=["test_enums.gd", "test_lambdas.gd"])
    args = parser.parse_args()
    library = args.library.resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="tree-sitter-gd-enums-") as directory:
        project = Path(directory)
        shutil.copy2(library, project / library.name)
        shutil.copy2(Path(__file__).with_name(args.suite), project / args.suite)
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
             "--log-file", str(project / "godot.log"), "--script", "res://" + args.suite],
            capture_output=True, text=True, timeout=60,
        )
        print(result.stdout, end="")
        print(result.stderr, end="")
        # Script parse errors may not cause Godot to return a nonzero exit code.
        marker = "PASS: lambda regressions" if args.suite == "test_lambdas.gd" else "PASS: unnamed enum regressions"
        if result.returncode or marker not in result.stdout or "SCRIPT ERROR" in result.stderr:
            raise SystemExit(result.returncode or 1)


if __name__ == "__main__":
    main()
