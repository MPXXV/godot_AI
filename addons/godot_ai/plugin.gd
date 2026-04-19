@tool
extends EditorPlugin

const AiPanel = preload("res://addons/godot_ai/ui/ai_panel.gd")

var _panel: Control


func _enter_tree() -> void:
	_panel = preload("res://addons/godot_ai/ui/ai_panel.tscn").instantiate()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _panel)


func _exit_tree() -> void:
	if _panel:
		remove_control_from_docks(_panel)
		_panel.queue_free()
		_panel = null
