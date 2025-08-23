#!/bin/bash
cmus-remote -C 'echo -e "Now Playing: %t by %a\n%b"'
info=$(cmus-remote -Q | awk -F ' ' '
/^tag title/ { title = substr($0, index($0,$3)) }
/^tag artist/ { artist = substr($0, index($0,$3)) }
/^tag album/ { album = substr($0, index($0,$3)) }
END { print title"\n"artist" — "album }')

notify-send "🎵 Now Playing" "$info"
