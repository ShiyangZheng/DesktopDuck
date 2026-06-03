# Desktop Duck 🦆

A desktop pet app for macOS — a floating window with an AI-powered duck (or capybara!) that chats, journals, and animates.

## Features

- **Desktop Pet**: Floating animated character (duck or capybara) with idle/walk animations
- **AI Chat**: Powered by MiniMax API — click the duck to chat
- **Journal**: Iterative document-based journal with AI summarization
- **Character Generator**: AI-generated spritesheet → GIF animation pipeline
- **Spritesheet Editor**: Upload/Generate → Grid adjustment → Convert → Apply
- **Preferences**: Full customization of appearance, bubbles, memory, and more

## Quick Start

```bash
# Compile the Swift app
swiftc -o duck-pet duck-pet.swift

# Bundle into an .app
mkdir -p DesktopDuck.app/Contents/MacOS
mkdir -p DesktopDuck.app/Contents/Resources
cp duck-pet DesktopDuck.app/Contents/MacOS/
cp pet-*.py DesktopDuck.app/Contents/Resources/
cp duck-idle.gif capybara.gif DesktopDuck.app/Contents/Resources/

# Open it
open DesktopDuck.app
```

## Configuration

Copy `duck-config.json.template` to `~/.workbuddy/duck-config.json` and fill in:

```json
{
  "llmApiKey": "your-minimax-api-key",
  "llmModel": "MiniMax-M2.7",
  "minimax_api_key": "your-minimax-api-key"
}
```

## Requirements

- macOS 12+
- Swift 5.9+
- Python 3 with Pillow (`pip install Pillow`)
- MiniMax API key for AI features

## Project Structure

- `duck-pet.swift` — Main Swift application
- `pet-auto-reply.py` — AI chat response engine
- `pet-think.py` — Thought injection bridge
- `pet-generate-character.py` — AI spritesheet generation
- `pet-convert-spritesheet.py` — Spritesheet → GIF conversion
- `pet-journal-summary.py` — Journal AI summarization
- `pet-random-content.py` — Random content/events
- `duck-idle.gif` — Default duck animation
- `capybara.gif` — Capybara alternative pet

## License

MIT
