# Setup fzf
# ---------
if [[ ! "$PATH" == */home/andres/.fzf/bin* ]]; then
  PATH="${PATH:+${PATH}:}/home/andres/.fzf/bin"
fi

# Auto-completion
# ---------------
source "/home/andres/.fzf/shell/completion.zsh"

# Key bindings
# ------------
# source "/home/andres/.fzf/shell/key-bindings.zsh"
