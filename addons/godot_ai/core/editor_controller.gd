@tool
extends RefCounted

# Creates a new .gd file with the given content and opens it in the editor.
# Returns an error string on failure, empty string on success.
static func create_script(file_path: String, content: String) -> String:
	# ensure path starts with res://
	if not file_path.begins_with("res://"):
		file_path = "res://" + file_path

	# ensure .gd extension
	if not file_path.ends_with(".gd"):
		file_path += ".gd"

	# make sure directory exists
	var dir := file_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		if err != OK:
			return "Could not create directory: %s" % dir

	# write file
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		return "Could not write file: %s" % file_path

	file.store_string(content)
	file.close()

	# refresh filesystem so Godot picks it up
	EditorInterface.get_resource_filesystem().scan()

	# open it in the script editor
	var script := load(file_path)
	if script and script is Script:
		EditorInterface.edit_script(script)

	return ""


# Opens an existing script by path or by filename search.
static func open_script(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "File not found: %s" % path

	var script := load(path)
	if not script or not script is Script:
		return "Not a valid script: %s" % path

	EditorInterface.edit_script(script)
	return ""


# Opens an existing scene by path.
static func open_scene(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "Scene not found: %s" % path

	EditorInterface.open_scene_from_path(path)
	return ""


static func create_node(node_type: String, parent_path: String = "") -> String:
	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return "No scene open"
	if not ClassDB.class_exists(node_type):
		return "Unknown node type: %s" % node_type

	var parent: Node
	if parent_path.is_empty():
		parent = scene_root
	else:
		parent = scene_root.get_node_or_null(parent_path)
		if not parent:
			return "Node not found: %s" % parent_path

	var new_node := ClassDB.instantiate(node_type) as Node
	if not new_node:
		return "Could not instantiate: %s" % node_type
	new_node.name = node_type

	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Create %s" % node_type)
	ur.add_do_method(parent, "add_child", new_node)
	ur.add_do_method(new_node, "set_owner", scene_root)
	ur.add_undo_method(parent, "remove_child", new_node)
	ur.commit_action()
	return ""


static func add_script_to_selected(script_content: String, filename: String = "") -> String:
	var selected := EditorInterface.get_selection().get_selected_nodes()
	if selected.is_empty():
		return "No node selected"
	var node := selected[0]

	if filename.is_empty():
		filename = node.name.to_snake_case() + ".gd"
	if not filename.ends_with(".gd"):
		filename += ".gd"
	var path := "res://" + filename

	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return "Could not write file: %s" % path
	file.store_string(script_content)
	file.close()

	EditorInterface.get_resource_filesystem().scan()
	var script := load(path)
	if not script or not script is Script:
		return "Could not load script: %s" % path

	var old_script: Variant = node.get_script()
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Add Script")
	ur.add_do_property(node, "script", script)
	ur.add_undo_property(node, "script", old_script)
	ur.commit_action()

	EditorInterface.edit_script(script)
	return ""


static func run_scene() -> String:
	EditorInterface.play_current_scene()
	return ""


static func create_scene(scene_name: String, root_node_type: String = "Node2D") -> String:
	if not ClassDB.class_exists(root_node_type):
		return "Unknown node type: %s" % root_node_type

	var root := ClassDB.instantiate(root_node_type) as Node
	if not root:
		return "Could not instantiate: %s" % root_node_type
	root.name = scene_name

	var scene := PackedScene.new()
	var pack_result := scene.pack(root)
	root.free()
	if pack_result != OK:
		return "Could not pack scene"

	var path := "res://" + scene_name + ".tscn"
	if ResourceSaver.save(scene, path) != OK:
		return "Could not save scene to: %s" % path

	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.open_scene_from_path(path)
	return ""


static func rename_node(node_path: String, new_name: String) -> String:
	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return "No scene open"
	var node := scene_root.get_node_or_null(node_path)
	if not node:
		return "Node not found: %s" % node_path

	var old_name := node.name
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Rename Node")
	ur.add_do_property(node, "name", new_name)
	ur.add_undo_property(node, "name", old_name)
	ur.commit_action()
	return ""
