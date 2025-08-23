#!/bin/bash

# Get current song info from cmus
artist=$(cmus-remote -Q 2>/dev/null | grep '^tag artist ' | cut -d ' ' -f 3-)
title=$(cmus-remote -Q 2>/dev/null | grep '^tag title ' | cut -d ' ' -f 3-)

if [[ -z "$artist" || -z "$title" ]]; then
    notify-send "cmus lyrics" "Missing artist or title tags."
    exit 1
fi

# Get lyrics
response=$(curl -s "https://api.lyrics.ovh/v1/${artist// /%20}/${title// /%20}")
lyrics=$(echo "$response" | jq -r '.lyrics')

if [[ "$lyrics" == "null" || -z "$lyrics" ]]; then
    notify-send "cmus lyrics" "Lyrics not found for: $title by $artist"
    exit 1
fi

# Write the lyrics to a temporary file
tmpfile="/tmp/cmus_lyrics.txt"
echo -e "$title by $artist\n\n$lyrics" > "$tmpfile"

# Get the window ID for any existing cmus-lyrics window
win_id=$(kitty @ ls | jq -r '
  .[] | .tabs[] | .windows[] |
  select(.foreground_processes[].cmdline | join(" ") | test("less")) |
  select(.title == "cmus-lyrics") |
  .id // empty
')

# If the window exists, close it
if [[ -n "$win_id" ]]; then
    kitty @ close-window --window-id "$win_id"
fi

# Open a new Kitty window with the lyrics
kitty --title "cmus-lyrics" less "$tmpfile" &
