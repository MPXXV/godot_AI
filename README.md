# Godot AI

An AI assistant built directly into the Godot 4 editor. Ask questions, get code, insert it — without leaving the editor.

![Godot AI panel](.github/preview.png)

## Features

- **Streaming chat** — answers appear in real time as the AI types
- **Auto context** — first message automatically includes your open script, scene tree, and project file list
- **@mention files** — type `@player.gd` to inject any file into your message
- **Attach files** — attach any `.gd`, `.tscn`, `.md` or `.txt` file with 📎
- **Insert code** — paste AI-generated code directly into the open script at cursor
- **Create scripts** — save AI code as a new `.gd` file, opens instantly in the editor
- **Editor actions** — AI can create nodes, add scripts, run scenes, and rename nodes directly
- **Project memory** — save key facts between sessions so AI remembers your project
- **Session history** — conversations persist when you restart Godot
- **Quick actions** — one-click Explain / Refactor / Comments / Find bugs for the open script
- **Multiple providers** — Anthropic Claude, OpenAI, Google Gemini, or local Ollama
- **Light / dark theme** — toggle to match your preference
- **Export chat** — save any conversation as a `.md` file

## Supported providers & models

| Provider | Models | Key needed |
|---|---|---|
| **Anthropic** (default) | claude-haiku-4-5-20251001, claude-sonnet-4-6, claude-opus-4-6 | [console.anthropic.com](https://console.anthropic.com) |
| **OpenAI** | gpt-5.4-mini, gpt-5.4, gpt-4.1-mini, gpt-4.1, o4-mini, o3 | [platform.openai.com](https://platform.openai.com) |
| **Gemini** | gemini-3.1-pro-preview, gemini-3.1-flash-lite-preview, gemini-2.5-pro, gemini-2.5-flash | [aistudio.google.com](https://aistudio.google.com) |
| **Ollama** | llama3.1, llama3.2, mistral, codestral, deepseek-coder-v2, phi4 | None — runs locally |

## Installation

1. Download or clone this repo
2. Copy the `addons/godot_ai/` folder into your project's `addons/` directory
3. Open Godot → **Project → Project Settings → Plugins** → enable **Godot AI**
4. Click **⚙** in the AI panel → select your provider → paste your API key → Save

API keys are stored in Godot's **EditorSettings** — never saved to project files, never committed to git.

## Usage tips

- **First message** automatically injects your current script, scene tree, and file list
- Type **@filename.gd** to pull in any specific file mid-conversation
- Click **💾 Save to memory** after important decisions — AI remembers them next session
- Press **✕** to start a fresh conversation when switching tasks
- **Shift+Enter** for a new line, **Enter** to send

## Ollama (local AI, free)

1. Install [Ollama](https://ollama.com)
2. Run `ollama pull codestral` (or any model you prefer)
3. In Godot AI settings: select **Ollama**, keep URL as `http://localhost:11434`, pick your model

## Security

- API keys live in Godot's **EditorSettings** (`editor_settings-*.tres`) — outside your project folder and never committed to git
- Nothing is sent to any server except your messages and the context you explicitly enable

## Contributing

PRs and issues welcome. Made by a Godot developer for Godot developers.

## License

MIT
