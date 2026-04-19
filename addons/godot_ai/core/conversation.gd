@tool
extends RefCounted

const MAX_MESSAGES := 40  # keep last 40 to stay within context

var _messages: Array = []


func add_user(text: String) -> void:
	_messages.append({"role": "user", "content": text})
	_trim()


func add_assistant(text: String) -> void:
	_messages.append({"role": "assistant", "content": text})
	_trim()


func get_messages() -> Array:
	return _messages.duplicate()


func clear() -> void:
	_messages.clear()


func is_empty() -> bool:
	return _messages.is_empty()


func _trim() -> void:
	while _messages.size() > MAX_MESSAGES:
		# Protect the first message pair (project context injected by ContextBuilder).
		# Remove from index 2 instead of 0 to preserve messages[0] and messages[1].
		var remove_idx := 2 if _messages.size() > 2 else 0
		_messages.remove_at(remove_idx)
