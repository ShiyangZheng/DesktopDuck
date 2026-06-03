# Desktop Duck 🦆

A desktop pet app for macOS — a floating window with an AI-powered duck (or capybara!) that chats, journals, animates, and now: runs group discussions with a buddy. **v1.3 brings local LLM support — run models entirely offline.**

![Desktop Pet](screenshots/pet.png)

## Quick Start

### Homebrew (recommended)

```bash
brew tap shiyangzheng/tap
brew install --cask desktop-duck
```

### Download from GitHub Releases

Download the latest `DesktopDuck-v*.app.zip` from [Releases](https://github.com/ShiyangZheng/DesktopDuck/releases), unzip, and drag `DesktopDuck.app` to `/Applications`.

### Manual Install from Source

```bash
# Compile the Swift app
swiftc -o duck-pet duck-pet.swift -framework AppKit -framework Foundation

# Bundle into an .app
mkdir -p 小鸭子.app/Contents/MacOS
mkdir -p 小鸭子.app/Contents/Resources
cp duck-pet 小鸭子.app/Contents/MacOS/
cp pet-*.py 小鸭子.app/Contents/Resources/
cp duck-idle.gif capybara.gif 小鸭子.app/Contents/Resources/
cp llama-server lib*.dylib 小鸭子.app/Contents/Resources/

# Open it
open 小鸭子.app
```

## 🆕 v1.3 — Local LLM & Offline AI

![Local LLM](screenshots/local_model.png)

Run your desktop pet entirely offline with a local language model:

- **Local LLM Support**: Download and run Qwen 2.5-7B (or any GGUF model) via bundled llama-server — no cloud API needed
- **Zero-Dependency Download**: Model downloads use pure Python stdlib (or pure `curl`/shell fallback) — no `pip install` required
- **One-Click Setup**: Enter a HuggingFace model name, click Download, wait for the 3.5GB model, then Start — your pet runs locally on Apple Silicon
- **Code-Enforced Group Chat Routing**: Group chat now uses deterministic routing (code decides who speaks to whom) — the LLM only generates content, ensuring identical conversation flow across cloud and local models
- **Smart Model Selection**: Automatically picks the best single-file GGUF (prioritizing q4_k_m > q3_k_m > q2_k), handles split-file models transparently
- **Health Monitoring**: Real-time server status display, warmup progress, and crash recovery

### v1.2 — Group Chat

![Group Chat](group_chat.jpg)

Two pets, one stage. From the menu bar, open **Group Chat**, configure both pets' personalities, and start a topic:

- **Dual Pets**: Duck and Capybara appear side by side for every session
- **Autonomous Multi-Turn Discussion**: You speak → pets discuss among themselves (2-3 rounds) → then respond to you
- **Color-Coded Bubbles**: Duck (warm cream), Capybara (ice blue), User (pure white)
- **Hover Glow**: Mouse over any bubble for a subtle highlight effect
- **Collapsible Stacks**: Multiple messages auto-fold; click to expand
- **Full Transcript**: Conversation log with bold speaker names and proper spacing
- **AI Session Summary**: Stop the session and receive an AI-generated discussion summary

## Features

- **Desktop Pet**: Floating animated character (duck or capybara) with idle/walk animations
- **AI Chat**: Powered by MiniMax API or local LLM — click the duck to chat, right-click for preferences
- **Group Chat** (v1.2): Dual-pet autonomous discussions with multi-turn pet-to-pet dialogue
- **Local LLM** 🆕 (v1.3): Download and run Qwen 2.5-7B offline — zero cloud API needed
- **Journal**: Iterative document-based journal with AI summarization
- **Character Generator**: AI-powered spritesheet → GIF animation pipeline — describe any character and get a custom animated pet in 6 frames
- **Spritesheet Editor**: Upload/Generate → Grid adjustment → Convert → Apply
- **Preferences**: Full customization of appearance, bubbles, memory, and more

## Screenshots

### Local LLM (v1.3)
![Local LLM](screenshots/local_model.png)

### Group Chat (v1.2)
![Group Chat](group_chat.jpg)

### Chat with AI
![Chat](screenshots/talk.png)

### Preferences
![Preferences](screenshots/preferences.png)

### AI Character Generator
Describe any character — pixel cat, robot, slime — and the AI generates a full spritesheet with 6 sequential animation poses (idle/walking/thinking/happy/sleepy/surprised), automatically sliced into per-frame GIFs with transparent backgrounds. Fine-tune frame boundaries by dragging grid lines directly on the preview, then convert and apply to your pet with one click.

![Character Generator](screenshots/generate.png)

### Journal
![Journal](screenshots/journal.png)



## Configuration

Copy `duck-config.json.template` to `~/.workbuddy/duck-config.json` and fill in:

**Cloud AI** (requires API key):
```json
{
  "llmApiKey": "your-minimax-api-key",
  "llmModel": "MiniMax-M2.7",
  "minimax_api_key": "your-minimax-api-key"
}
```

**Local LLM** (no API key needed):
```json
{
  "llmProvider": "local",
  "localModelName": "Qwen/Qwen2.5-7B-Instruct-GGUF",
  "localServerPort": 8090,
  "localModelDir": "/Users/yourname/.workbuddy/models/"
}
```

For group chat:
```json
{
  "groupChatEnabled": true,
  "groupPets": [
    {"name": "Duck", "personality": "cheerful and energetic", "thinking": "optimistic"},
    {"name": "Capybara", "personality": "calm and wise", "thinking": "analytical"}
  ]
}
```

## Requirements

- macOS 12+
- Swift 5.9+
- Python 3 (built-in on macOS 13+) — required for local LLM download/server management
- MiniMax API key for cloud AI features (optional if using local LLM)
- ~3.5GB free disk space for the default local model (Qwen 2.5-7B GGUF)

## Project Structure

- `duck-pet.swift` — Main Swift application with local LLM UI
- `pet-llm-server.py` — 🆕 Local LLM download & server manager (zero dependencies, v1.3)
- `llama-server` — 🆕 Bundled llama.cpp inference engine
- `pet-group-chat.py` — 🆕 Group chat AI orchestration engine (code-enforced routing, v1.2/1.3)
- `pet-auto-reply.py` — AI chat response engine (supports cloud + local LLM)
- `pet-think.py` — Thought injection bridge
- `pet-generate-character.py` — AI spritesheet generation
- `pet-convert-spritesheet.py` — Spritesheet → GIF conversion
- `pet-journal-summary.py` — Journal AI summarization
- `pet-random-content.py` — Random content/events
- `duck-idle.gif` — Default duck animation
- `capybara.gif` — Capybara alternative pet
- `group_chat.jpg` — Group chat screenshot (v1.2)
- `screenshots/local_model.png` — 🆕 Local LLM screenshot (v1.3)

## Platform

This is a native macOS application built with Swift and AppKit. **Windows is not currently supported** — the app relies on macOS-specific frameworks (NSWindow, AppKit, CGWindow, NSStatusBar, etc.). A cross-platform rewrite would require a different UI framework.

## License

MIT
