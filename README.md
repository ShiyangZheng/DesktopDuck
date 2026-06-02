# DesktopDuck 🦆

A cute AI-powered desktop pet duck for macOS. Lives on your desktop, chats with you via LLM, keeps a mindfulness journal, and can even generate custom character art.

Built with Swift + AppKit, powered by the MiniMax API (or any OpenAI-compatible endpoint).

<img src="duck-idle.gif" width="64" height="64" alt="Duck pet preview">

## Features

- **Desktop Pet** — Borderless animated duck that lives on your desktop
- **AI Chat** — Double-click to chat with the duck via LLM (MiniMax, OpenAI, or any compatible API)
- **Journal System** — 5 mindfulness templates (Odyssey Plan, Wheel of Life, 12 Month Celebration, Fear Setting, Solomon's Paradox) + custom prompts
- **AI Journal Summary** — After each journal entry, the LLM generates a reflective summary
- **AI Character Generation** — Describe a character and the app generates a custom pet image via MiniMax image-01
- **Configurable** — Everything adjustable via Preferences: size, bubbles, timeout, context window, window level
- **Bubble Stack** — Messages appear as floating bubbles above the duck, with scrollable, auto-expiring options
- **Window Levels** — Always on Top / Normal / Always at Bottom
- **Status Bar Menu** — Quick access to Preferences, Journal, and quit

## Requirements

- **macOS 13+** (Ventura or later)
- **Python 3.7+** with `Pillow` (for character generation)
- **MiniMax API key** (or any OpenAI-compatible API)

Install Pillow:
```bash
pip3 install Pillow
```

## Quick Start

### Option 1: Download Release (Recommended)

1. Download `DesktopDuck.zip` from the [latest release](https://github.com/ShiyangZheng/DesktopDuck/releases/latest)
2. Unzip and move `DesktopDuck.app` to your Applications folder
3. On first launch, right-click → **Open** (to bypass Gatekeeper)
4. Open Preferences (right-click duck → Preferences, or ⌘,) and enter your API key
5. Double-click the duck to start chatting!

### Option 2: Build from Source

```bash
# Clone the repo
git clone https://github.com/ShiyangZheng/DesktopDuck.git
cd DesktopDuck

# Build the app
swiftc -o duck-pet duck-pet.swift

# Set up the app bundle
mkdir -p DesktopDuck.app/Contents/{MacOS,Resources}
cp duck-pet DesktopDuck.app/Contents/MacOS/
cp duck-idle.gif pet-auto-reply.py pet-generate-character.py \
   pet-journal-summary.py pet-random-content.py pet-think.py \
   DesktopDuck.app/Contents/Resources/

# Create Info.plist (or use the included one)

# Set up config
mkdir -p ~/.workbuddy
cp duck-config.json.template ~/.workbuddy/duck-config.json
# Edit ~/.workbuddy/duck-config.json to add your API key

# Launch
./DesktopDuck.app/Contents/MacOS/duck-pet &
```

## Configuration

All settings live in `~/.workbuddy/duck-config.json`. The Preferences panel (right-click → Preferences) provides a GUI for everything.

### Key Settings

| Setting | Description | Default |
|---------|-------------|---------|
| `minimax_api_key` | Your MiniMax API key (required) | — |
| `llmModel` | Model name | `MiniMax-M2.7` |
| `llmUrl` | API endpoint | `https://api.minimax.io/v1/chat/completions` |
| `user_name` | What the duck calls you | (empty) |
| `ai_name` | What the duck calls itself | `Duck` |
| `scale` | Duck size multiplier (1–8) | `2.0` |
| `windowLevel` | 0=bottom, 1=normal, 2=top | `2` |
| `bubbleTimeout` | Seconds before bubbles auto-dismiss (0=never) | `0` |

### Using OpenAI Instead of MiniMax

Set in `duck-config.json`:
```json
{
  "minimax_api_key": "sk-your-openai-key",
  "llmUrl": "https://api.openai.com/v1/chat/completions",
  "llmModel": "gpt-4o-mini"
}
```

Any OpenAI-compatible endpoint works (Ollama, Groq, etc.).

## Usage

| Action | How |
|--------|-----|
| **Chat** | Double-click the duck |
| **Quick reply** | Click the duck (random fun fact) |
| **Close bubble** | Click the ✕ on a bubble |
| **Move duck** | Drag the duck anywhere |
| **Preferences** | Right-click → Preferences or ⌘, |
| **Journal Entry** | Right-click → Journal Entry |
| **View Journal** | Right-click → View Journal |
| **Window Level** | Right-click → Always on Top / Normal / Always at Bottom |
| **Clear History** | Right-click → Clear Chat History |

### Journal Templates

1. **Odyssey Plan** — Design 3 radically different 5-year futures
2. **Wheel of Life** — Rate satisfaction across 8 life dimensions
3. **12 Month Celebration** — Write toasts celebrating your future achievements
4. **Fear Setting** — Define, prevent, and repair worst-case scenarios
5. **Solomon's Paradox** — Get perspective by talking about yourself in third person

After each journal session, view your entries and click **Refresh** to generate AI-powered summaries.

### Character Generation

1. Open Preferences → scroll to "Generate Character Image"
2. Describe your character (e.g., "cute pixel art cat, chibi style")
3. Click **Generate** — MiniMax image-01 creates the character
4. Preview appears — click **Apply** to use it as your pet
5. Click **Restore Default Duck** to go back

## File Structure

```
DesktopDuck/
├── duck-pet.swift              # Main Swift application
├── duck-idle.gif               # Default duck sprite
├── pet-auto-reply.py           # AI chat engine
├── pet-generate-character.py   # AI image generation + GIF creation
├── pet-journal-summary.py      # AI journal summary generator
├── pet-random-content.py       # Fun fact generator
├── pet-think.py                # External communication helper
├── kill.sh                     # Stop the duck
├── duck-config.json.template   # Config template
├── DesktopDuck.app/            # Built app bundle (not in git)
└── README.md
```

### User Data (stored in `~/.workbuddy/`)

- `duck-config.json` — Your configuration (API key, preferences)
- `chat-history.json` — Chat conversation history
- `journal.json` — Journal entries and AI summaries
- `pet-thoughts.json` — Real-time communication between processes
- `duck-custom/` — Generated character images

## License

MIT License — see [LICENSE](LICENSE) file.

## Credits

Built with ❤️ using Swift, AppKit, and the MiniMax API. Original duck GIF from [keyfarm](https://keyfarm.itch.io/) (MIT licensed).
