#!/bin/bash
# Kill all desktop pets regardless of binary name
for name in duck-pet ducky capybara-pet; do
    killall -9 "$name" 2>/dev/null
done
pkill -9 -f "duck-pet\|ducky" 2>/dev/null
rm -f ~/.workbuddy/duck-pet.pid ~/.workbuddy/capybara-pet.pid ~/.workbuddy/duck-prefs.json
sleep 0.5
pgrep -l "duck\|capybara" 2>/dev/null && echo "⚠️ Zombies remain" || echo "🦆 All pets killed"
