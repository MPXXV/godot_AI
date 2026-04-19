@tool
extends Node

signal response_chunk(text: String)
signal response_done(full_text: String)
signal response_error(message: String)

enum Provider { ANTHROPIC, OPENAI, GEMINI, OLLAMA }

const MAX_TOKENS := 2048
const MODEL_DEFAULT := "claude-haiku-4-5-20251001"

var _http := HTTPClient.new()
var _streaming := false
var _full_text := ""
var _buffer := ""
var _provider := Provider.ANTHROPIC


func _process(_delta: float) -> void:
	if not _streaming:
		return

	_http.poll()
	var status := _http.get_status()

	match status:
		HTTPClient.STATUS_REQUESTING:
			pass
		HTTPClient.STATUS_BODY:
			var chunk := _http.read_response_body_chunk()
			if chunk.size() > 0:
				_buffer += chunk.get_string_from_utf8()
				_process_buffer()
		HTTPClient.STATUS_CONNECTED:
			_finish()
		HTTPClient.STATUS_DISCONNECTED, HTTPClient.STATUS_CONNECTION_ERROR:
			_finish()


func send(messages: Array, system_prompt: String = "") -> void:
	_provider = _get_provider()

	var headers := _build_headers()
	if headers.is_empty():
		return

	var body_str := _build_body(messages, system_prompt)
	if body_str.is_empty():
		return

	var url_info := _parse_url(_get_host())
	var tls_opts = TLSOptions.client() if url_info.use_tls else null
	var err := _http.connect_to_host(url_info.host, url_info.port, tls_opts)
	if err != OK:
		response_error.emit("Could not connect (err %d)" % err)
		return

	while _http.get_status() == HTTPClient.STATUS_CONNECTING \
			or _http.get_status() == HTTPClient.STATUS_RESOLVING:
		_http.poll()
		await get_tree().process_frame

	if _http.get_status() != HTTPClient.STATUS_CONNECTED:
		response_error.emit("Connection failed")
		return

	var path := _get_path()
	err = _http.request(HTTPClient.METHOD_POST, path, headers, body_str)
	if err != OK:
		response_error.emit("Request failed (err %d)" % err)
		return

	_full_text = ""
	_buffer = ""
	_streaming = true


func _get_provider() -> Provider:
	var p: String = ProjectSettings.get_setting("godot_ai/provider", "Anthropic")
	match p:
		"OpenAI": return Provider.OPENAI
		"Gemini": return Provider.GEMINI
		"Ollama": return Provider.OLLAMA
		_: return Provider.ANTHROPIC


func _get_host() -> String:
	match _provider:
		Provider.OPENAI:
			return "https://api.openai.com"
		Provider.GEMINI:
			return "https://generativelanguage.googleapis.com"
		Provider.OLLAMA:
			var url: String = ProjectSettings.get_setting(
				"godot_ai/ollama_url", "http://localhost:11434")
			return url
		_:
			return "https://api.anthropic.com"


func _parse_url(url: String) -> Dictionary:
	var use_tls := url.begins_with("https://")
	var rest := url.substr(8 if use_tls else 7)
	var slash_idx := rest.find("/")
	if slash_idx >= 0:
		rest = rest.left(slash_idx)
	var default_port := 443 if use_tls else 80
	var host := rest
	var port := default_port
	var colon_idx := rest.rfind(":")
	if colon_idx >= 0:
		host = rest.left(colon_idx)
		port = int(rest.substr(colon_idx + 1))
	return {"host": host, "port": port, "use_tls": use_tls}


func _get_path() -> String:
	var model: String = ProjectSettings.get_setting("godot_ai/model", MODEL_DEFAULT)
	match _provider:
		Provider.OPENAI:
			return "/v1/chat/completions"
		Provider.GEMINI:
			return "/v1beta/models/%s:streamGenerateContent?alt=sse" % model
		Provider.OLLAMA:
			return "/api/chat"
		_:
			return "/v1/messages"


func _build_headers() -> Array:
	match _provider:
		Provider.OPENAI:
			var key := _get_key("godot_ai/openai_api_key")
			if key.is_empty():
				response_error.emit("OpenAI API key not set. Click ⚙ to add it.")
				return []
			return [
				"Content-Type: application/json",
				"Authorization: Bearer " + key,
			]
		Provider.GEMINI:
			var key := _get_key("godot_ai/gemini_api_key")
			if key.is_empty():
				response_error.emit("Gemini API key not set. Click ⚙ to add it.")
				return []
			return [
				"Content-Type: application/json",
				"x-goog-api-key: " + key,
			]
		Provider.OLLAMA:
			return ["Content-Type: application/json"]
		_:
			var key := _get_key("godot_ai/api_key")
			if key.is_empty():
				response_error.emit("API key not set. Click ⚙ to add it.")
				return []
			return [
				"Content-Type: application/json",
				"x-api-key: " + key,
				"anthropic-version: 2023-06-01",
			]


func _build_body(messages: Array, system_prompt: String) -> String:
	var model: String = ProjectSettings.get_setting("godot_ai/model", MODEL_DEFAULT)

	match _provider:
		Provider.GEMINI:
			# Gemini uses a different format
			var contents: Array = []
			if not system_prompt.is_empty():
				contents.append({
					"role": "user",
					"parts": [{"text": "System: " + system_prompt}]
				})
				contents.append({
					"role": "model",
					"parts": [{"text": "Understood."}]
				})
			for msg in messages:
				var role: String = msg.get("role", "user")
				var gemini_role := "model" if role == "assistant" else "user"
				contents.append({
					"role": gemini_role,
					"parts": [{"text": msg.get("content", "")}]
				})
			return JSON.stringify({
				"contents": contents,
				"generationConfig": {"maxOutputTokens": MAX_TOKENS}
			})

		Provider.OPENAI, Provider.OLLAMA:
			var msgs: Array = []
			if not system_prompt.is_empty():
				msgs.append({"role": "system", "content": system_prompt})
			msgs.append_array(messages)
			var body := {
				"model": model,
				"stream": true,
				"messages": msgs,
			}
			if _provider == Provider.OPENAI:
				# o3 and o4-mini use max_completion_tokens, others use max_tokens
				var is_reasoning := model.begins_with("o3") or model.begins_with("o4")
				if is_reasoning:
					body["max_completion_tokens"] = MAX_TOKENS
				else:
					body["max_tokens"] = MAX_TOKENS
			return JSON.stringify(body)

		_:
			# Anthropic
			var body := {
				"model": model,
				"max_tokens": MAX_TOKENS,
				"stream": true,
				"messages": messages,
			}
			if not system_prompt.is_empty():
				body["system"] = system_prompt
			return JSON.stringify(body)


func _process_buffer() -> void:
	while "\n" in _buffer:
		var idx := _buffer.find("\n")
		var line := _buffer.left(idx).strip_edges()
		_buffer = _buffer.substr(idx + 1)

		if line.is_empty():
			continue

		var data: String
		if line.begins_with("data: "):
			data = line.substr(6)
			if data == "[DONE]":
				continue
		elif _provider == Provider.OLLAMA:
			data = line
		else:
			continue

		var json := JSON.new()
		if json.parse(data) != OK:
			continue

		var obj: Dictionary = json.get_data()
		var text := ""

		match _provider:
			Provider.GEMINI:
				var candidates: Array = obj.get("candidates", [])
				if not candidates.is_empty():
					var parts: Array = candidates[0].get("content", {}).get("parts", [])
					if not parts.is_empty():
						text = parts[0].get("text", "")

			Provider.OPENAI, Provider.OLLAMA:
				var choices: Array = obj.get("choices", [])
				if not choices.is_empty():
					var delta: Dictionary = choices[0].get("delta", {})
					text = delta.get("content", "")
				if text.is_empty():
					var msg: Dictionary = obj.get("message", {})
					text = msg.get("content", "")

			_:
				# Anthropic
				if obj.get("type") != "content_block_delta":
					continue
				var delta: Dictionary = obj.get("delta", {})
				if delta.get("type") != "text_delta":
					continue
				text = delta.get("text", "")

		if not text.is_empty():
			_full_text += text
			response_chunk.emit(text)


func _finish() -> void:
	if not _streaming:
		return
	_streaming = false
	_http.close()
	if _full_text.is_empty():
		response_error.emit("Empty response from API")
	else:
		response_done.emit(_full_text)


func stop() -> void:
	if _streaming:
		_streaming = false
		_http.close()
		if not _full_text.is_empty():
			response_done.emit(_full_text)


func _get_key(setting: String) -> String:
	var es := EditorInterface.get_editor_settings()
	return es.get_setting(setting) if es.has_setting(setting) else ""
