#!/bin/bash
# Launch DesktopDuck
cd "$(dirname "$0")"
if [ -f "DesktopDuck.app/Contents/MacOS/duck-pet" ]; then
    nohup ./DesktopDuck.app/Contents/MacOS/duck-pet > /dev/null 2>&1 &
    echo "DesktopDuck launched!"
elif [ -f "duck-pet" ]; then
    nohup ./duck-pet > /dev/null 2>&1 &
    echo "DesktopDuck launched (from source)!"
else
    echo "Build first: swiftc -o duck-pet duck-pet.swift"
fi
