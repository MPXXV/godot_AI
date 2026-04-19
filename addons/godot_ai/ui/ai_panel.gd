@tool
extends Control

const AiClient = preload("res://addons/godot_ai/core/ai_client.gd")
const ContextBuilder = preload("res://addons/godot_ai/core/context_builder.gd")
const Conversation = preload("res://addons/godot_ai/core/conversation.gd")
const MemoryManager = preload("res://addons/godot_ai/core/memory_manager.gd")
const EditorController = preload("res://addons/godot_ai/core/editor_controller.gd")
const ProjectScanner = preload("res://addons/godot_ai/core/project_scanner.gd")
const SessionStore = preload("res://addons/godot_ai/core/session_store.gd")

const SYSTEM_PROMPT_BASE := """You are a helpful Godot 4 game development assistant \
built directly into the editor. You help with GDScript, scene architecture, \
debugging, and game design. Be concise and practical. \
When writing code, always use GDScript 4 syntax. \
When the developer mentions a filename, you can refer to its contents \
if they have been provided in the context. \
When writing a complete new script meant to be saved as its own file, \
start the first code block with a comment like: # filename: my_script.gd \
Always reply in the same language the user writes in.
When the user asks you to create a node, add a script, run the scene, create a scene, or rename a node — emit an action block at the END of your response:
```action
{"action": "create_node", "args": {"node_type": "Sprite2D", "parent_path": ""}}
```
Available actions: create_node, add_script_to_selected, run_scene, create_scene, rename_node."""

# theme color sets
const THEME_DARK := {
	"user": "bbbbbb", "assistant": "ffffff",
	"error": "ff6b6b", "label": "888888", "code": "89b4fa"
}
const THEME_LIGHT := {
	"user": "444444", "assistant": "111111",
	"error": "cc2222", "label": "999999", "code": "2563eb"
}

@onready var _chat_log: RichTextLabel = %ChatLog
@onready var _input: TextEdit = %Input
@onready var _send_btn: Button = %SendButton
@onready var _stop_btn: Button = %StopButton
@onready var _clear_btn: Button = %ClearButton
@onready var _session_btn: Button = %SessionButton
@onready var _memory_toggle_btn: Button = %MemoryToggleButton
@onready var _memory_panel: VBoxContainer = %MemoryPanel
@onready var _memory_list: VBoxContainer = %MemoryList
@onready var _settings_btn: Button = %SettingsButton
@onready var _export_btn: Button = %ExportButton
@onready var _context_btn: Button = %ContextButton
@onready var _theme_btn: Button = %ThemeButton
@onready var _context_check: CheckBox = %ContextCheck
@onready var _status: Label = %StatusLabel
@onready var _token_label: Label = %TokenLabel
@onready var _insert_btn: Button = %InsertButton
@onready var _create_btn: Button = %CreateButton
@onready var _memory_btn: Button = %MemoryButton
@onready var _attach_btn: Button = %AttachButton
@onready var _attach_label: Label = %AttachLabel

var _client: AiClient
var _conversation := Conversation.new()
var _memory := MemoryManager.new()
var _session_store := SessionStore.new()
var _current_session_id := ""
var _display_messages: Array = []
var _last_code_block := ""
var _last_suggested_filename := ""
var _is_streaming := false
var _stream_text := ""
var _total_chars := 0
var _is_dark_theme := true
var _attached_path := ""
var _attached_content := ""
var _code_blocks: Array = []


func _ready() -> void:
	_memory.load_memory()

	_client = AiClient.new()
	add_child(_client)
	_client.response_chunk.connect(_on_chunk)
	_client.response_done.connect(_on_done)
	_client.response_error.connect(_on_error)

	_send_btn.pressed.connect(_on_send)
	_stop_btn.pressed.connect(_on_stop)
	_clear_btn.pressed.connect(_on_clear)
	_session_btn.pressed.connect(_on_show_sessions)
	_memory_toggle_btn.pressed.connect(_on_toggle_memory_panel)
	_settings_btn.pressed.connect(_on_settings)
	_export_btn.pressed.connect(_on_export)
	_context_btn.pressed.connect(_on_show_context)
	_theme_btn.pressed.connect(_on_toggle_theme)
	_insert_btn.pressed.connect(_on_insert_code)
	_create_btn.pressed.connect(_on_create_script)
	_memory_btn.pressed.connect(_on_save_memory)
	_attach_btn.pressed.connect(_on_attach_file)
	_input.gui_input.connect(_on_input_key)
	_chat_log.meta_clicked.connect(_on_meta_clicked)

	$VBox/QuickActions/ExplainBtn.pressed.connect(
		func(): _quick_action("Explain what this script does, step by step."))
	$VBox/QuickActions/RefactorBtn.pressed.connect(
		func(): _quick_action("Suggest refactoring improvements for this script. Focus on readability and GDScript best practices."))
	$VBox/QuickActions/CommentsBtn.pressed.connect(
		func(): _quick_action("Add clear, concise comments to this script. Return the full commented script."))
	$VBox/QuickActions/BugsBtn.pressed.connect(
		func(): _quick_action("Review this script for bugs, logic errors, and potential issues. List anything you find."))

	_insert_btn.visible = false
	_create_btn.visible = false
	_memory_btn.visible = false
	_stop_btn.visible = false
	_attach_label.text = ""
	_set_status("")
	_token_label.text = ""

	_current_session_id = _session_store.generate_id()

	if not _has_api_key():
		_push_message("error", "⚠ API key not set. Click ⚙ to add your Anthropic API key.")
		_redraw_log()
		return

	# try to restore previous session
	if _load_session():
		_redraw_log()
		_set_status("Session restored")
		await get_tree().create_timer(2.0).timeout
		_set_status("")
		return

	var greeting := "Hi! I'm your Godot AI assistant."
	if not _memory.is_empty():
		greeting += " I remember %d things about your project." % _memory.get_entries().size()
	_push_message("assistant", greeting)
	_redraw_log()


func _has_api_key() -> bool:
	var es := EditorInterface.get_editor_settings()
	var provider: String = ProjectSettings.get_setting("godot_ai/provider", "Anthropic")
	match provider:
		"OpenAI":
			return es.has_setting("godot_ai/openai_api_key") \
				and not es.get_setting("godot_ai/openai_api_key").is_empty()
		"Gemini":
			return es.has_setting("godot_ai/gemini_api_key") \
				and not es.get_setting("godot_ai/gemini_api_key").is_empty()
		"Ollama":
			return true
		_:
			return es.has_setting("godot_ai/api_key") \
				and not es.get_setting("godot_ai/api_key").is_empty()


# --- session persistence ---

func _save_session() -> void:
	_session_store.save_session(_current_session_id, _display_messages, _total_chars)


func _load_session() -> bool:
	var sessions := _session_store.list_sessions()
	if sessions.is_empty():
		return false
	var latest: Dictionary = sessions[0]
	var data := _session_store.load_session(latest.get("id", ""))
	if data.is_empty():
		return false
	var msgs: Array = data.get("messages", [])
	if msgs.is_empty():
		return false
	_current_session_id = latest.get("id", _current_session_id)
	_display_messages = msgs
	_total_chars = data.get("total_chars", 0)
	for msg in msgs:
		var role: String = msg.get("role", "")
		var text: String = msg.get("content", msg.get("text", ""))
		if role == "user":
			_conversation.add_user(text)
		elif role == "assistant":
			_conversation.add_assistant(text)
	_update_token_label()
	return true


func _load_session_data(id: String) -> void:
	var data := _session_store.load_session(id)
	if data.is_empty():
		return
	var msgs: Array = data.get("messages", [])
	if msgs.is_empty():
		return
	_conversation.clear()
	_display_messages = msgs
	_total_chars = data.get("total_chars", 0)
	_current_session_id = id
	for msg in msgs:
		var role: String = msg.get("role", "")
		var text: String = msg.get("content", msg.get("text", ""))
		if role == "user":
			_conversation.add_user(text)
		elif role == "assistant":
			_conversation.add_assistant(text)
	_update_token_label()
	_redraw_log()


# --- theme ---

func _on_toggle_theme() -> void:
	_is_dark_theme = not _is_dark_theme
	_theme_btn.text = "☀" if _is_dark_theme else "🌙"
	_redraw_log()


func _get_colors() -> Dictionary:
	return THEME_DARK if _is_dark_theme else THEME_LIGHT


# --- attach file ---

func _on_attach_file() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.filters = ["*.gd,*.tscn,*.tres,*.shader,*.gdshader,*.md,*.txt ; Project files"]
	dialog.title = "Attach file to message"
	add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))
	dialog.file_selected.connect(func(path: String) -> void:
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			_attached_content = file.get_as_text()
			file.close()
			_attached_path = path
			_attach_label.text = "📎 " + path.get_file()
			_attach_btn.text = "✕"
			_attach_btn.pressed.disconnect(_on_attach_file)
			_attach_btn.pressed.connect(_on_clear_attachment)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)


func _on_clear_attachment() -> void:
	_attached_path = ""
	_attached_content = ""
	_attach_label.text = ""
	_attach_btn.text = "📎"
	_attach_btn.pressed.disconnect(_on_clear_attachment)
	_attach_btn.pressed.connect(_on_attach_file)


func _build_system_prompt() -> String:
	var parts := [SYSTEM_PROMPT_BASE]
	var mem := _memory.build_prompt_block()
	if not mem.is_empty():
		parts.append(mem)
	return "\n\n".join(parts)


# --- send / stream ---

func _on_send() -> void:
	if _is_streaming:
		return
	var text := _input.text.strip_edges()
	if text.is_empty():
		return
	_input.text = ""
	_send_text(text)


func _send_text(text: String) -> void:
	_insert_btn.visible = false
	_create_btn.visible = false
	_memory_btn.visible = false
	_set_busy(true)

	var full_text := text

	if _context_check.button_pressed and _conversation.is_empty():
		var ctx := ContextBuilder.build()
		if not ctx.is_empty():
			full_text = ctx + "\n\n---\n\n" + text

	var file_ctx := ContextBuilder.build_for_query(text)
	if not file_ctx.is_empty():
		full_text += "\n\n" + file_ctx

	# @mention — e.g. @player.gd injects that file
	var mention_ctx := _resolve_mentions(text)
	if not mention_ctx.is_empty():
		full_text += "\n\n" + mention_ctx

	# inject manually attached file
	if not _attached_content.is_empty():
		var ext := _attached_path.get_extension()
		var lang := "gdscript" if ext == "gd" else ext
		full_text += "\n\n### Attached: %s\n```%s\n%s\n```" % [
			_attached_path.get_file(), lang, _attached_content
		]
		_on_clear_attachment()

	_push_message("user", text)
	_redraw_log()
	_conversation.add_user(full_text)
	_total_chars += full_text.length()

	_push_message("assistant", "")
	_stream_text = ""
	_is_streaming = true

	_client.send(_conversation.get_messages(), _build_system_prompt())


func _on_chunk(chunk: String) -> void:
	_stream_text += chunk
	_display_messages[-1]["text"] = _stream_text
	_redraw_log()


func _on_done(full_text: String) -> void:
	_is_streaming = false
	_conversation.add_assistant(full_text)
	_total_chars += full_text.length()
	var stripped_text := _strip_action_block(full_text)
	_display_messages[-1]["text"] = stripped_text

	_redraw_log()
	_update_token_label()
	_save_session()

	var code := _extract_first_code_block(stripped_text)
	if not code.is_empty():
		_last_code_block = code
		var suggested := _extract_suggested_filename(stripped_text)
		if not suggested.is_empty():
			_last_suggested_filename = suggested
			_create_btn.text = "📄 Create %s" % suggested
			_create_btn.visible = true
		else:
			_last_suggested_filename = ""
			_create_btn.visible = false
		_insert_btn.visible = true

	_memory_btn.visible = true
	_set_busy(false)

	var action_status := _parse_and_run_action(full_text)
	if not action_status.is_empty():
		_set_status(action_status)
		get_tree().create_timer(3.0).timeout.connect(func(): _set_status(""))


func _on_error(message: String) -> void:
	_is_streaming = false
	_display_messages[-1] = {"role": "error", "text": message}
	_redraw_log()
	_set_busy(false)


func _on_stop() -> void:
	_client.stop()
	_is_streaming = false
	_set_busy(false)


# --- quick actions ---

func _quick_action(prompt: String) -> void:
	if _is_streaming:
		return
	_on_clear()
	_send_text(prompt)


# --- log rendering ---

func _push_message(role: String, text: String) -> void:
	_display_messages.append({"role": role, "text": text})


func _redraw_log() -> void:
	var c := _get_colors()
	_code_blocks.clear()
	_chat_log.clear()
	for msg in _display_messages:
		var role: String = msg["role"]
		var text: String = msg["text"]

		if role == "user":
			_chat_log.append_text("[right][color=#666666][font_size=10]YOU[/font_size][/color][/right]\n")
			_chat_log.append_text("[right][color=#%s]%s[/color][/right]\n\n" % [c.user, text])
		elif role == "assistant":
			_chat_log.append_text("[color=#666666][font_size=10]AI[/font_size][/color]\n")
			if not text.is_empty():
				_chat_log.append_text(_format_message(text))
			_chat_log.append_text("\n\n")
		else:
			_chat_log.append_text("[color=#%s]%s[/color]\n\n" % [c.error, text])


func _resolve_mentions(text: String) -> String:
	# detect @filename.gd / @filename.tscn etc in message
	var regex := RegEx.new()
	regex.compile("@([\\w_]+\\.(?:gd|tscn|shader|gdshader|tres|md|txt))")
	var matches := regex.search_all(text)
	if matches.is_empty():
		return ""
	var parts: PackedStringArray = []
	var seen: Array = []
	for m in matches:
		var filename := m.get_string(1)
		if filename in seen:
			continue
		seen.append(filename)
		var found := ProjectScanner.find_files_by_name(filename.get_basename())
		for path in found:
			var content := ProjectScanner.read_file(path)
			if not content.is_empty():
				var ext: String = path.get_extension()
				var lang: String = "gdscript" if ext == "gd" else ext
				parts.append("### @%s\n```%s\n%s\n```" % [filename, lang, content])
	return "\n\n".join(parts)


func _format_message(text: String) -> String:
	var c := _get_colors()
	var result := ""
	var lines := text.split("\n")
	var in_code := false
	var code_lang := ""
	var code_buf := ""

	# GDScript keywords for syntax highlighting
	const KW_COLOR := "f8c555"  # amber — keywords
	const KW_BUILTIN := "7ec8e3"  # teal — built-in types
	const KW_STRING := "98c379"  # green — strings
	const KEYWORDS := ["func", "var", "const", "if", "elif", "else", "for",
		"while", "match", "return", "class", "extends", "signal", "enum",
		"static", "pass", "break", "continue", "and", "or", "not", "in",
		"is", "as", "self", "null", "true", "false", "await", "yield"]
	const BUILTINS := ["int", "float", "bool", "String", "Array", "Dictionary",
		"Vector2", "Vector3", "Color", "Node", "Control", "void"]

	var inline_re := RegEx.new()
	inline_re.compile("`([^`]+)`")
	var bold_re := RegEx.new()
	bold_re.compile("\\*\\*(.+?)\\*\\*")

	for i in lines.size():
		var line: String = lines[i]

		if line.begins_with("```"):
			if in_code:
				var idx := _code_blocks.size()
				_code_blocks.append(code_buf.strip_edges())
				code_buf = ""
				result += "[/color][/font_size] [url=copy::%d]📋[/url]\n" % idx
				in_code = false
				code_lang = ""
			else:
				code_lang = line.substr(3).strip_edges().to_lower()
				result += "[font_size=11][color=#89b4fa]"
				in_code = true
			continue

		if in_code:
			code_buf += line + "\n"
			if code_lang == "gdscript" or code_lang == "gd" or code_lang == "":
				result += _highlight_gdscript_line(line, KW_COLOR, KW_BUILTIN, KW_STRING, c.code, KEYWORDS, BUILTINS) + "\n"
			else:
				result += "[color=#%s]%s[/color]\n" % [c.code, line]
			continue

		# inline `code`
		var formatted := line
		for m in inline_re.search_all(line):
			formatted = formatted.replace(
				m.get_string(0),
				"[color=#%s]%s[/color]" % [c.code, m.get_string(1)]
			)

		# **bold**
		for m in bold_re.search_all(formatted):
			formatted = formatted.replace(
				m.get_string(0), "[b]%s[/b]" % m.get_string(1)
			)

		result += "[color=#%s]%s[/color]" % [c.assistant, formatted]
		if i < lines.size() - 1:
			result += "\n"

	if in_code:
		result += "[/color][/font_size]"

	return result


func _highlight_gdscript_line(
	line: String,
	kw_color: String,
	builtin_color: String,
	str_color: String,
	default_color: String,
	keywords: Array,
	builtins: Array
) -> String:
	# handle full-line comments
	var stripped := line.strip_edges()
	if stripped.begins_with("#"):
		return "[color=#6a9955]%s[/color]" % line  # green comments

	# simple token-by-token coloring
	var result := ""
	var i := 0
	var chars := line.length()

	while i < chars:
		var ch := line[i]

		# comment from here to end
		if ch == "#":
			result += "[color=#6a9955]%s[/color]" % line.substr(i)
			break

		# string literals
		if ch == '"' or ch == "'":
			var quote := ch
			var j := i + 1
			while j < chars and line[j] != quote:
				if line[j] == "\\" and j + 1 < chars:
					j += 1
				j += 1
			var token := line.substr(i, j - i + 1)
			result += "[color=#%s]%s[/color]" % [str_color, token]
			i = j + 1
			continue

		# word token — check if keyword or builtin
		if ch.unicode_at(0) == 95 or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z"):
			var j := i
			while j < chars:
				var c2 := line[j]
				if c2.unicode_at(0) == 95 or (c2 >= "a" and c2 <= "z") \
						or (c2 >= "A" and c2 <= "Z") or (c2 >= "0" and c2 <= "9"):
					j += 1
				else:
					break
			var word := line.substr(i, j - i)
			if word in keywords:
				result += "[color=#%s]%s[/color]" % [kw_color, word]
			elif word in builtins:
				result += "[color=#%s]%s[/color]" % [builtin_color, word]
			else:
				result += "[color=#%s]%s[/color]" % [default_color, word]
			i = j
			continue

		# number
		if ch >= "0" and ch <= "9":
			var j := i
			while j < chars and (line[j] >= "0" and line[j] <= "9" or line[j] == "."):
				j += 1
			result += "[color=#d19a66]%s[/color]" % line.substr(i, j - i)
			i = j
			continue

		result += ch
		i += 1

	return result


# --- actions ---

func _on_clear() -> void:
	_conversation.clear()
	_display_messages.clear()
	_last_code_block = ""
	_last_suggested_filename = ""
	_stream_text = ""
	_total_chars = 0
	_insert_btn.visible = false
	_create_btn.visible = false
	_memory_btn.visible = false
	_token_label.text = ""
	_current_session_id = _session_store.generate_id()
	_push_message("assistant", "Conversation cleared. How can I help?")
	_redraw_log()


func _on_settings() -> void:
	var dialog := preload("res://addons/godot_ai/ui/settings_dialog.tscn").instantiate()
	add_child(dialog)
	dialog.popup_centered()


func _on_show_context() -> void:
	var content := _build_system_prompt()
	if _context_check.button_pressed:
		var ctx := ContextBuilder.build()
		if not ctx.is_empty():
			content += "\n\n---\n\n" + ctx
	var token_count := content.length() / 4

	var win := Window.new()
	win.title = "Context sent to AI"
	win.size = Vector2i(400, 500)
	win.wrap_controls = true

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	win.add_child(vbox)

	var edit := TextEdit.new()
	edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit.editable = false
	edit.text = content
	vbox.add_child(edit)

	var lbl := Label.new()
	lbl.text = "~%d tokens" % token_count
	lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(lbl)

	add_child(win)
	win.popup_centered()
	win.close_requested.connect(win.queue_free)


func _on_show_sessions() -> void:
	var win := Window.new()
	win.title = "Chat history"
	win.size = Vector2i(360, 400)
	win.wrap_controls = true
	add_child(win)
	win.popup_centered()
	win.close_requested.connect(win.queue_free)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	win.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	_populate_session_list(list, win)


func _populate_session_list(list: VBoxContainer, win: Window) -> void:
	for child in list.get_children():
		child.queue_free()
	var sessions := _session_store.list_sessions()
	if sessions.is_empty():
		var lbl := Label.new()
		lbl.text = "No saved chats"
		list.add_child(lbl)
		return
	for entry in sessions:
		var sid: String = entry.get("id", "")
		var title: String = entry.get("title", "New chat")
		var updated: int = int(entry.get("updated_at", 0))
		var dt := Time.get_datetime_dict_from_unix_time(updated)
		var date_str := "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]
		var row := HBoxContainer.new()
		var load_btn := Button.new()
		load_btn.text = title + "\n" + date_str
		load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		load_btn.flat = true
		load_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		load_btn.pressed.connect(func():
			_load_session_data(sid)
			win.queue_free()
		)
		var del_btn := Button.new()
		del_btn.text = "✕"
		del_btn.flat = true
		del_btn.pressed.connect(func():
			_session_store.delete_session(sid)
			_populate_session_list(list, win)
		)
		row.add_child(load_btn)
		row.add_child(del_btn)
		list.add_child(row)


func _on_export() -> void:
	if _display_messages.is_empty():
		return
	var md := "# Godot AI — Chat export\n\n"
	for msg in _display_messages:
		var role: String = msg["role"]
		var text: String = msg["text"]
		var label := {"user": "**You**", "assistant": "**AI**", "error": "**Error**"}.get(role, "")
		md += "%s\n\n%s\n\n---\n\n" % [label, text]
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.filters = ["*.md ; Markdown files"]
	dialog.current_file = "godot_ai_chat.md"
	dialog.title = "Export chat"
	add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))
	dialog.file_selected.connect(func(path: String) -> void:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(md)
			file.close()
			_set_status("Exported!")
		dialog.queue_free()
		await get_tree().create_timer(2.0).timeout
		_set_status("")
	)
	dialog.canceled.connect(dialog.queue_free)


func _on_insert_code() -> void:
	if _last_code_block.is_empty():
		return
	var script_editor := EditorInterface.get_script_editor()
	if not script_editor:
		_set_status("No script editor open")
		return
	var current_editor := script_editor.get_current_editor()
	if not current_editor:
		_set_status("Open a script first")
		return
	var code_edit := _find_code_edit(current_editor)
	if not code_edit:
		_set_status("Could not access script editor")
		return
	code_edit.insert_text_at_caret("\n" + _last_code_block + "\n")
	_set_status("Code inserted!")
	await get_tree().create_timer(2.0).timeout
	_set_status("")


func _on_create_script() -> void:
	if _last_code_block.is_empty():
		return
	var filename := _last_suggested_filename if not _last_suggested_filename.is_empty() else "new_script.gd"
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.filters = ["*.gd ; GDScript files"]
	dialog.current_file = filename
	dialog.title = "Save new script"
	add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))
	dialog.file_selected.connect(func(path: String) -> void:
		var err := EditorController.create_script(path, _last_code_block)
		if err.is_empty():
			_set_status("Created: " + path.get_file())
		else:
			_set_status("Error: " + err)
		dialog.queue_free()
		await get_tree().create_timer(3.0).timeout
		_set_status("")
	)
	dialog.canceled.connect(dialog.queue_free)


func _on_save_memory() -> void:
	_set_status("Saving to memory...")
	_memory_btn.disabled = true
	var msgs := _conversation.get_messages()
	if msgs.size() < 2:
		_set_status("Nothing to save yet")
		_memory_btn.disabled = false
		return
	var user_msg: String = msgs[-2].get("content", "").substr(0, 500)
	var ai_msg: String = msgs[-1].get("content", "").substr(0, 500)
	var last_exchange := "User: %s\nAI: %s" % [user_msg, ai_msg]
	var summary_prompt := [{"role": "user", "content": (
		"Summarise the key fact or decision from this exchange "
		+ "in ONE short sentence (max 15 words). "
		+ "Write only the sentence, no preamble.\n\n" + last_exchange
	)}]
	var temp_client := AiClient.new()
	add_child(temp_client)
	temp_client.response_done.connect(func(fact: String) -> void:
		_memory.add_entry(fact)
		_refresh_memory_list()
		_set_status("Saved: " + fact)
		temp_client.queue_free()
		_memory_btn.disabled = false
		await get_tree().create_timer(3.0).timeout
		_set_status("")
	)
	temp_client.response_error.connect(func(_e: String) -> void:
		_set_status("Could not save to memory")
		temp_client.queue_free()
		_memory_btn.disabled = false
	)
	temp_client.send(summary_prompt)


func _on_toggle_memory_panel() -> void:
	_memory_panel.visible = not _memory_panel.visible
	if _memory_panel.visible:
		_refresh_memory_list()


func _refresh_memory_list() -> void:
	for child in _memory_list.get_children():
		child.queue_free()
	var entries := _memory.get_entries()
	for i in entries.size():
		var idx := i
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = entries[i]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var btn := Button.new()
		btn.text = "✕"
		btn.flat = true
		btn.pressed.connect(func(): _memory.remove_entry(idx); _refresh_memory_list())
		row.add_child(lbl)
		row.add_child(btn)
		_memory_list.add_child(row)
	_memory_toggle_btn.tooltip_text = "Memory (%d)" % entries.size()


func _on_input_key(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER and not event.shift_pressed:
			_on_send()
			get_viewport().set_input_as_handled()


# --- helpers ---

func _on_meta_clicked(meta: Variant) -> void:
	var s := str(meta)
	if not s.begins_with("copy::"):
		return
	var idx := s.substr(6).to_int()
	if idx < 0 or idx >= _code_blocks.size():
		return
	DisplayServer.clipboard_set(_code_blocks[idx])
	_set_status("Copied!")
	get_tree().create_timer(2.0).timeout.connect(func(): _set_status(""))


func _strip_action_block(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("```action\\n[\\s\\S]*?```")
	return regex.sub(text, "", true).strip_edges()


func _parse_and_run_action(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("```action\\n([\\s\\S]*?)```")
	var m := regex.search(text)
	if not m:
		return ""
	var json := JSON.new()
	if json.parse(m.get_string(1).strip_edges()) != OK:
		return "Action parse error"
	var data: Dictionary = json.get_data()
	var action: String = data.get("action", "")
	var args: Dictionary = data.get("args", {})
	var err := ""
	match action:
		"create_node":
			err = EditorController.create_node(
				args.get("node_type", "Node"),
				args.get("parent_path", "")
			)
		"add_script_to_selected":
			err = EditorController.add_script_to_selected(
				args.get("script_content", ""),
				args.get("filename", "")
			)
		"run_scene":
			err = EditorController.run_scene()
		"create_scene":
			err = EditorController.create_scene(
				args.get("scene_name", "new_scene"),
				args.get("root_node_type", "Node2D")
			)
		"rename_node":
			err = EditorController.rename_node(
				args.get("node_path", ""),
				args.get("new_name", "")
			)
		_:
			return "Unknown action: %s" % action
	return ("Action error: " + err) if not err.is_empty() else ("✓ %s done" % action)


func _update_token_label() -> void:
	_token_label.text = "~%d tokens" % (_total_chars / 4)


func _extract_first_code_block(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("```(?:gdscript)?\\n([\\s\\S]*?)```")
	var m := regex.search(text)
	if m:
		return m.get_string(1).strip_edges()
	return ""


func _extract_suggested_filename(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("# filename:\\s*([\\w_/]+\\.gd)")
	var m := regex.search(text)
	if m:
		return m.get_string(1).get_file()
	return ""


func _find_code_edit(node: Node) -> CodeEdit:
	if node is CodeEdit:
		return node as CodeEdit
	for child in node.get_children():
		var result := _find_code_edit(child)
		if result:
			return result
	return null


func _set_busy(busy: bool) -> void:
	_send_btn.visible = not busy
	_stop_btn.visible = busy
	_input.editable = not busy
	_set_status("")


func _set_status(text: String) -> void:
	_status.text = text
