# Add user configurations here
# For HyDE not to touch your beloved configurations,
# we added 2 files to the project structure:
# 1. ~/.hyde.zshrc - for customizing the shell related hyde configurations
# 2. ~/.zshenv - for updating the zsh environment variables handled by HyDE // this will be modified across updates

#  Plugins 
# oh-my-zsh plugins are loaded  in ~/.hyde.zshrc file, see the file for more information
plugins=(
    fzf
    sudo
    git                     # (default)
    zsh-autosuggestions     # (default)
    zsh-syntax-highlighting # (default)
    zsh-completions         # (default)
    extract
    zsh-history-substring-search
    web-search
)

#  Aliases 
# Add aliases here
alias c='clear' \
    ls='eza -1 -lha --icons=always --sort=extension --group-directories-first --show-symlinks --no-permissions --no-user --no-time --no-filesize' \
    in='${PM_COMMAND[@]} install' \
    un='${PM_COMMAND[@]} remove' \
    up='${PM_COMMAND[@]} upgrade' \
    pl='${PM_COMMAND[@]} search installed' \
    pa='${PM_COMMAND[@]} search all' \
    vc='vscodium' \
    fastfetch='fastfetch --logo-type kitty' \
    ..='cd ..' \
    ...='cd ../..' \
    .3='cd ../../..' \
    .4='cd ../../../..' \
    .5='cd ../../../../..' \
    mkdir='mkdir -p' \
    ffec='_fuzzy_edit_search_file_content' \
    ffcd='_fuzzy_change_directory' \
    ffe='_fuzzy_edit_search_file' \
    ff='fastfetch' \

#  This is your file 
# Add your configurations here
# export EDITOR=nvim
export EDITOR=vscodium

# ====== My settings ======


# === Speed up Oh My Zsh ===
ZSH_DISABLE_COMPFIX=true

# Tab completion
autoload -Uz compinit
compinit -i
zstyle ':completion:*' menu select
zstyle ':completion:*' rehash true
zstyle ':completion:*' verbose true
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.zsh/cache

# === Prompt Setup ===
# Toggle between Powerlevel10k and Starship
USE_STARSHIP=true # Set to "false" to use Powerlevel10k

if [[ "$USE_STARSHIP" == "true" ]]; then
    eval "$(starship init zsh)"
elif [[ -f /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme ]]; then
    source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme
    [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
fi

# === Starship Configuration Aliases ===
alias starship-edit='vscodium ~/starship.toml'
alias zshrc-edit='vscodium ~/.zshrc'
alias zsh-reload='source ~/.zshrc'

# History
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000
setopt hist_ignore_all_dups
setopt share_history
setopt append_history
setopt inc_append_history

# eval "$(zoxide init zsh)"
export PATH=$PATH:/home/andres/.spicetify

# Starship
eval "$(starship init zsh)"

# Proton
export PROTON_NO_WINDOWED=1
export PROTON_FULLSCREEN=1

# bun completions
[ -s "/home/andres/.bun/_bun" ] && source "/home/andres/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Set up fzf key bindings and fuzzy completion
source <(fzf --zsh)
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# source /share/zsh-history-substring-search/zsh-history-substring-search.zsh
source /home/andres/.oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
# source /home/andres/.oh-my-zsh/custom/plugins/web-search/web-search.plugin.zsh
export PAGER=most
# opencode
export PATH=/home/andres/.opencode/bin:$PATH

export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
