extends SceneTree

var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	test_constants()
	test_scopes()
	test_incremental()
	test_incomplete()
	if failures == 0:
		print("PASS: unnamed enum regressions")
	quit(0 if failures == 0 else 1)

func test_constants() -> void:
	var source := "enum { A, B }\nenum { C, D }\nenum {\n\tNEG = -3,\n\tNEXT,\n\tBITS = 1 << 4,\n\tAFTER,\n\tREF = BITS | 2,\n\tLAST,\n}\nenum Named { HIDDEN, OTHER = 5 }\nconst ORDINARY: int = 42\n"
	var parser := GDScriptTreeParser.new()
	parser.open_text(source)
	var scope: Dictionary = parser.parse_script("res://fixture.gd")[""]
	var constants: Dictionary = scope.constants
	var expected := {
		"A": "0", "B": "A + 1", "C": "0", "D": "C + 1",
		"NEG": "-3", "NEXT": "NEG + 1", "BITS": "1 << 4",
		"AFTER": "BITS + 1", "REF": "BITS | 2", "LAST": "REF + 1",
	}
	check(constants.size() == expected.size() + 2, "only real constants and named enum")
	for name in expected:
		check(constants.has(name), "constant exists: " + name)
		if not constants.has(name):
			continue
		var info: Dictionary = constants[name]
		check(info.member_type == &"const" and typeof(info.member_type) == TYPE_STRING_NAME, "constant kind: " + name)
		check(info.member_name == StringName(name), "member name: " + name)
		check(info.type == &"int" and typeof(info.type) == TYPE_STRING_NAME, "integer type: " + name)
		check(info.has_static_type, "known integer type: " + name)
		check(info.assignment == expected[name], "assignment: " + name)
		check(info.access_path == &"" and info.script_path == &"res://fixture.gd", "constant origin: " + name)
	check(constants.get("NEG", {}).get("line_index") == 3, "entry line")
	check(constants.get("NEG", {}).get("column_index") == 1, "entry column")
	check(constants.get("NEXT", {}).get("line_index") == 4, "next entry line")
	check(constants.get("Named", {}).get("member_type") == &"enum", "named enum representation")
	check(not constants.has("HIDDEN"), "named enum entries stay scoped")
	check(constants.get("ORDINARY", {}).get("assignment") == "42", "ordinary constant preserved")
	check(scope.members.is_empty(), "constants belong in constants dictionary")

	var symbols: Dictionary = parser.sparse_parse().members
	var names: Array = symbols[""].constants
	check(names.size() == constants.size(), "sparse constant count")
	for name in constants:
		check(names.has(StringName(name)), "sparse constant: " + name)
	parser.update_text("\n\n" + source)
	check(parser.sparse_parse().members == symbols, "line shifts preserve sparse symbols")
	check(hash(parser.sparse_parse().members) == hash(symbols), "line shifts preserve sparse hash")

	var query := GDScriptTreeQuery.new()
	query.open_text(source)
	var queried: Dictionary = query.get_constants("")
	check(queried.size() == constants.size(), "query constant count")
	for name in expected:
		var info: Dictionary = queried.get(name, {})
		check(info.get("keyword") == "const" and info.get("type") == "int", "query integer constant: " + name)
		check(info.get("line") == constants.get(name, {}).get("line_index"), "query entry position: " + name)
	check(queried.get("Named", {}).get("keyword") == "enum", "query named enum preserved")
	check(not queried.get("Named", {}).has("type"), "query named enum shape preserved")

func test_scopes() -> void:
	# The root enum follows the inner classes to exercise forward visibility.
	var source := "class Inner:\n\tenum { LOCAL = 9, FOLLOW }\n\tclass Deep:\n\t\tpass\nclass Sibling:\n\tpass\nenum { ROOT, ROOT_NEXT }\n"
	var parser := GDScriptTreeParser.new()
	parser.open_text(source)
	var scopes: Dictionary = parser.parse_script("res://scopes.gd")
	for path in ["", "Inner", "Inner.Deep", "Sibling"]:
		var constants: Dictionary = scopes[path].constants
		check(constants.has("ROOT"), "root enum visible in " + path)
		check(constants.get("ROOT", {}).get("access_path") == &"", "inherited constant keeps origin in " + path)
	for path in ["Inner", "Inner.Deep"]:
		var constants: Dictionary = scopes[path].constants
		check(constants.get("LOCAL", {}).get("access_path") == &"Inner", "inner enum origin in " + path)
		check(constants.get("FOLLOW", {}).get("assignment") == "LOCAL + 1", "inner enum sequence in " + path)
	check(not scopes[""].constants.has("LOCAL"), "inner enum does not leak to root")
	check(not scopes["Sibling"].constants.has("LOCAL"), "inner enum does not leak to sibling")
	var sparse: Dictionary = parser.sparse_parse().members
	check(sparse["Inner"].constants == [&"LOCAL", &"FOLLOW"], "sparse own constants only")
	check(sparse["Inner.Deep"].constants.is_empty(), "sparse excludes inherited constants")
	var query := GDScriptTreeQuery.new()
	query.open_text(source)
	check(query.get_constants("Inner").keys() == ["LOCAL", "FOLLOW"], "query inner constants")
	check(query.get_constants("Inner.Deep").is_empty(), "query excludes inherited constants")

func test_incremental() -> void:
	var source := "enum { A = 2, B, C }\nenum Named { X, Y }\n"
	var query := GDScriptTreeQuery.new()
	query.open_text(source)
	check(query.get_constants("", true).is_empty(), "fresh parse has no changed entries")
	var offset := source.find("2")
	query.apply_edit(offset, offset + 1, offset + 1, 0, offset, 0, offset + 1, 0, offset + 1)
	check(query.get_constants("").is_empty(), "queries suppressed before reparse")
	query.reparse_text(source.replace("2", "7"))
	var all: Dictionary = query.get_constants("")
	var changed: Dictionary = query.get_constants("", true)
	check(all.has_all(["A", "B", "C"]), "entries survive incremental value edit")
	for name in ["A", "B", "C"]:
		check(all.get(name, {}).get("changed") == all.get("A", {}).get("changed"), "enum entries share declaration change flag")
		check(changed.has(name) == all.get(name, {}).get("changed"), "changed_only follows declaration flag")
	query.update_text(source.replace("B,", "RENAMED,"))
	check(query.get_constants("").has("RENAMED") and not query.get_constants("").has("B"), "incremental rename refreshes names")
	var parser := GDScriptTreeParser.new()
	parser.open_text(source)
	parser.update_text(source.replace("B,", "RENAMED,"))
	check(parser.parse_script("")[""].constants.C.assignment == "RENAMED + 1", "implicit assignment follows renamed predecessor")
	check(parser.sparse_parse().members[""].constants.has(&"RENAMED"), "sparse reflects rename")

func test_incomplete() -> void:
	var parser := GDScriptTreeParser.new()
	var query := GDScriptTreeQuery.new()
	for source in ["enum {", "enum { A,", "enum { A, = 2, B }", "enum { A = }", "enum {}"]:
		parser.open_text(source)
		query.open_text(source)
		var full: Dictionary = parser.parse_script("")
		var sparse: Dictionary = parser.sparse_parse()
		for constants in [full[""].constants, query.get_constants("")]:
			for name in constants:
				check(not str(name).is_empty() and not str(name).begins_with("@anon_enum_"), "valid names in incomplete input")
		for name in sparse.members[""].constants:
			check(not str(name).is_empty() and not str(name).begins_with("@anon_enum_"), "valid sparse names in incomplete input")
