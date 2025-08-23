#!/bin/bash

# Launch media-related terminal applications in Kitty
kitty --title "cmus-term" -e cmus &
sleep 0.75

kitty --title "btop-term" -e btop &
sleep 0.5

kitty --title "cava-term" -e cava &