@tool
extends Window

@onready var _provider_option: OptionButton = %ProviderOption
@onready var _anthropic_key_input: LineEdit = %AnthropicKeyInput
@onready var _openai_key_input: LineEdit = %OpenAIKeyInput
@onready var _gemini_key_input: LineEdit = %GeminiKeyInput
@onready var _ollama_url_input: LineEdit = %OllamaUrlInput
@onready var _model_option: OptionButton = %ModelOption
@onready var _anthropic_section: VBoxContainer = %AnthropicSection
@onready var _openai_section: VBoxContainer = %OpenAISection
@onready var _gemini_section: VBoxContainer = %GeminiSection
@onready var _ollama_section: VBoxContainer = %OllamaSection
@onready var _save_btn: Button = %SaveButton
@onready var _cancel_btn: Button = %CancelButton

const PROVIDERS := ["Anthropic", "OpenAI", "Gemini", "Ollama"]

const MODELS := {
	"Anthropic": [
		"claude-haiku-4-5-20251001",
		"claude-sonnet-4-6",
		"claude-opus-4-6",
	],
	"OpenAI": [
		"gpt-5.4-mini",
		"gpt-5.4",
		"gpt-4.1-mini",
		"gpt-4.1",
		"o4-mini",
		"o3",
	],
	"Gemini": [
		"gemini-3.1-pro-preview",
		"gemini-3.1-flash-lite-preview",
		"gemini-2.5-pro",
		"gemini-2.5-flash",
	],
	"Ollama": [
		"llama3.1",
		"llama3.2",
		"mistral",
		"codestral",
		"deepseek-coder-v2",
		"phi4",
	],
}


func _ready() -> void:
	title = "Godot AI — Settings"
	min_size = Vector2i(460, 280)

	for p in PROVIDERS:
		_provider_option.add_item(p)

	_load_settings()
	_update_ui()

	_provider_option.item_selected.connect(func(_i: int) -> void:
		_populate_models()
		_update_ui()
	)
	_save_btn.pressed.connect(_on_save)
	_cancel_btn.pressed.connect(queue_free)
	close_requested.connect(queue_free)


func _populate_models(select_model: String = "") -> void:
	var provider: String = PROVIDERS[_provider_option.selected]
	var model_list: Array = MODELS.get(provider, [])
	_model_option.clear()
	for m in model_list:
		_model_option.add_item(m)
	# try to re-select previously saved model
	if not select_model.is_empty():
		var idx := model_list.find(select_model)
		_model_option.select(max(idx, 0))


func _update_ui() -> void:
	var provider: String = PROVIDERS[_provider_option.selected]
	_anthropic_section.visible = (provider == "Anthropic")
	_openai_section.visible = (provider == "OpenAI")
	_gemini_section.visible = (provider == "Gemini")
	_ollama_section.visible = (provider == "Ollama")


func _load_settings() -> void:
	var es := EditorInterface.get_editor_settings()

	var provider: String = ProjectSettings.get_setting("godot_ai/provider", "Anthropic")
	_provider_option.select(max(PROVIDERS.find(provider), 0))

	if es.has_setting("godot_ai/api_key"):
		_anthropic_key_input.text = es.get_setting("godot_ai/api_key")
	if es.has_setting("godot_ai/openai_api_key"):
		_openai_key_input.text = es.get_setting("godot_ai/openai_api_key")
	if es.has_setting("godot_ai/gemini_api_key"):
		_gemini_key_input.text = es.get_setting("godot_ai/gemini_api_key")

	_ollama_url_input.text = ProjectSettings.get_setting(
		"godot_ai/ollama_url", "http://localhost:11434")

	var saved_model: String = ProjectSettings.get_setting(
		"godot_ai/model", MODELS["Anthropic"][0])

	_populate_models(saved_model)


func _on_save() -> void:
	var es := EditorInterface.get_editor_settings()
	var provider: String = PROVIDERS[_provider_option.selected]

	es.set_setting("godot_ai/api_key", _anthropic_key_input.text.strip_edges())
	es.set_setting("godot_ai/openai_api_key", _openai_key_input.text.strip_edges())
	es.set_setting("godot_ai/gemini_api_key", _gemini_key_input.text.strip_edges())

	ProjectSettings.set_setting("godot_ai/provider", provider)
	ProjectSettings.set_setting("godot_ai/ollama_url", _ollama_url_input.text.strip_edges())

	var model_list: Array = MODELS.get(provider, [])
	var model: String = model_list[_model_option.selected] if not model_list.is_empty() else ""
	ProjectSettings.set_setting("godot_ai/model", model)
	ProjectSettings.save()
	queue_free()
