# Enum regression tests

Build the debug extension, then run the headless integration tests with a compatible
Godot executable and the resulting library. The runner creates a temporary project
and removes it when finished; no addon installation is needed.

```sh
scons target=template_debug -j8
python3 tests/run_enum_tests.py --godot /path/to/godot --library bin/libtree_sitter_gd.macos.template_debug.universal.dylib
```

Use the corresponding debug `.so` or `.dll` on Linux or Windows. The tests cover
full, sparse, and granular query output, nested scopes, expression text, incremental
edits, and incomplete editor input.
