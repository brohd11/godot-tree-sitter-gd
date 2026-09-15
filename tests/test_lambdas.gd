extends SceneTree

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	var source := "var assigned = func(a: int) -> int: return a\nvar callbacks = [func(x): return x, func(y): return y]\nfunc run():\n\tvar before: int = 1\n\tconnect(\"done\", func(value: String):\n\t\tvar own = value\n\t\tcall_deferred(\"go\", func(): return before)\n\t)\n\tvar local = func(): return 2\n\tvar after = 3\nclass Inner:\n\tvar f = func(): return 4\n"
	var parser := GDScriptTreeParser.new()
	var query := GDScriptTreeQuery.new()
	parser.open_text(source)
	query.open_text(source)
	var scopes: Dictionary = parser.parse_script("res://fixture.gd")
	var root: Dictionary = scopes[""]
	var queried: Dictionary = query.get_members("")
	var closures: Dictionary = query.get_lambdas("")
	check(root.lambdas.size() == 3 and closures.size() == 3, "class owns assigned and array callbacks only")
	check(root.lambdas.keys() == closures.keys(), "query/full keys agree")
	check(root.members.assigned.lambda == root.lambdas.assigned, "legacy payload preserved")
	check(root.lambdas.assigned.owner_variable == "assigned", "assigned binding")
	check(root.lambdas.assigned.args.a.type == &"int", "typed lambda argument")
	check(root.lambdas.assigned.return_type == &"int", "lambda return type")
	check(query.get_lambdas("Inner").keys() == ["f"], "inner class isolation")
	check(query.get_lambdas("missing").is_empty(), "unknown scope")
	for data in [root.members.run, queried.run]:
		check(data.lambdas.size() == 2, "function owns callback and local lambda")
		var callback: Dictionary = data.lambdas["inline_lambda_4_17"]
		check(callback.owner_variable == "", "callback has no binding")
		check(callback.lambdas.size() == 1, "nested callback")
		check(callback.locals.size() == 1, "lambda owns local")
		check(data.locals.size() == 3, "lambda locals excluded from function")
	check(root.members.run.locals["local-8-1"].lambda == root.members.run.lambdas["local-8-1"], "local legacy payload")
	check(not queried.has("lambdas"), "flat query preserved")
	check(query.get_lambdas("", true).is_empty(), "fresh parse change flags")
	var collision := "var inline_lambda_1_9 = func(): pass\nvar a = [func(): pass]\n"
	query.open_text(collision)
	check(query.get_lambdas("").has("inline_lambda_1_9_1"), "assigned names reserved")
	query.open_text("var a = [\"é\", func(): pass, func(): pass]\n")
	check(query.get_lambdas("").has("inline_lambda_0_15"), "UTF-8 byte column")
	query.open_text("func run():\n\tif true:\n\t\tvar f = func(): pass\n\telse:\n\t\tvar f = 1\n")
	check(not query.get_members("").run.locals.f.has("lambda"), "shadowed local does not inherit another binding's closure")
	for incomplete in ["var a = [func(", "func run():\n\tcall(func():\n\t\tpass", "# func(): pass\nvar a = \"func(): pass\"\n"]:
		query.open_text(incomplete)
		query.get_members("")
		query.get_lambdas("")
		parser.open_text(incomplete)
		parser.parse_script("")
	check(query.get_lambdas("").is_empty(), "comments and strings ignored")
	query.open_text(source)
	var offset := source.find("return a") + 7
	query.apply_edit(offset, offset + 1, offset + 1, 0, offset, 0, offset + 1, 0, offset + 1)
	check(query.get_lambdas("").is_empty(), "edited tree suppressed")
	query.reparse_text(source.left(offset) + "1" + source.substr(offset + 1))
	var changed: Dictionary = query.get_lambdas("", true)
	for name in query.get_lambdas(""):
		check(changed.has(name) == query.get_lambdas("")[name].changed, "lambda change filtering")
	query.update_text("var a = 1\n")
	check(query.get_lambdas("").is_empty(), "deleted lambdas removed")
	if failures == 0:
		print("PASS: lambda regressions")
	quit(1 if failures else 0)
