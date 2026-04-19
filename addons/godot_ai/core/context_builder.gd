@tool
extends RefCounted

const ProjectScanner = preload("res://addons/godot_ai/core/project_scanner.gd")

const MAX_SCRIPT_CHARS := 6000
const MAX_SCENE_DEPTH := 4


# full context for first message in a conversation
static func build(include_script: bool = true, include_scene: bool = true) -> String:
	var parts: PackedStringArray = []

	if include_script:
		var script_text := _get_current_script()
		if not script_text.is_empty():
			parts.append("### Current script\n```gdscript\n%s\n```" % script_text)

	if include_scene:
		var scene_text := _get_scene_tree_text()
		if not scene_text.is_empty():
			parts.append("### Scene tree\n```\n%s\n```" % scene_text)

	var file_tree := ProjectScanner.get_file_tree()
	if not file_tree.is_empty():
		parts.append("### Project files\n```\n%s\n```" % file_tree)

	if parts.is_empty():
		return ""

	return (
		"The developer is working in the Godot 4 editor.\n\n"
		+ "\n\n".join(parts)
	)


# builds extra context for a specific user query —
# auto-detects file names mentioned and injects their contents
static func build_for_query(query: String) -> String:
	var parts: PackedStringArray = []

	# look for .gd / .tscn mentions in the query
	var regex := RegEx.new()
	regex.compile("([\\w_]+\\.(?:gd|tscn|shader|gdshader|tres))")
	var matches := regex.search_all(query)

	for m in matches:
		var filename := m.get_string(1)
		var found := ProjectScanner.find_files_by_name(filename.get_basename())
		for path in found:
			var content := ProjectScanner.read_file(path)
			if not content.is_empty():
				var ext: String = path.get_extension()
				var lang: String = "gdscript" if ext == "gd" else ext
				parts.append(
					"### %s\n```%s\n%s\n```" % [path.get_file(), lang, content]
				)

	if parts.is_empty():
		return ""

	return "\n\n".join(parts)


static func _get_current_script() -> String:
	var script_editor := EditorInterface.get_script_editor()
	if not script_editor:
		return ""

	var current := script_editor.get_current_script()
	if not current:
		return ""

	var source: String = current.source_code
	if source.length() > MAX_SCRIPT_CHARS:
		source = source.left(MAX_SCRIPT_CHARS) + "\n# ... (truncated)"

	return source


static func _get_scene_tree_text() -> String:
	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return ""
	return _node_to_text(root, 0)


static func _node_to_text(node: Node, depth: int) -> String:
	if depth > MAX_SCENE_DEPTH:
		return ""

	var indent := "  ".repeat(depth)
	var script_hint := ""

	if node.get_script():
		script_hint = " [%s]" % node.get_script().resource_path.get_file()

	var line := "%s%s (%s)%s" % [indent, node.name, node.get_class(), script_hint]
	var lines := PackedStringArray([line])

	for child in node.get_children():
		var child_text := _node_to_text(child, depth + 1)
		if not child_text.is_empty():
			lines.append(child_text)

	return "\n".join(lines)
