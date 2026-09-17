[[ -x /opt/homebrew/bin/brew ]] || {
  print -u2 'Homebrew is required; run ~/.config/scripts/bootstrap.sh'
  return 1
}
eval "$(/opt/homebrew/bin/brew shellenv)"

ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
required_shell_files=(
  "$ZINIT_HOME/zinit.zsh"
  /opt/homebrew/opt/fzf/shell/completion.zsh
  /opt/homebrew/opt/fzf/shell/key-bindings.zsh
  "$HOME/.config/zsh/secrets.zsh"
)
for required_shell_file in "${required_shell_files[@]}"; do
  [[ -r "$required_shell_file" ]] || {
    print -u2 "Required shell file is missing: $required_shell_file"
    return 1
  }
done

for required_shell_command in starship zoxide; do
  command -v "$required_shell_command" >/dev/null 2>&1 || {
    print -u2 "Required shell command is missing: $required_shell_command"
    return 1
  }
done

source "$ZINIT_HOME/zinit.zsh"
zinit light zsh-users/zsh-completions

fpath=("$HOME/.zsh/completions" $fpath)
autoload -Uz compinit
if [[ ! -f "${ZDOTDIR:-$HOME}/.zcompdump" || "${ZDOTDIR:-$HOME}/.zcompdump" -ot "${ZDOTDIR:-$HOME}/.zshrc" ]]; then
  compinit
else
  compinit -C
fi

source /opt/homebrew/opt/fzf/shell/completion.zsh
source /opt/homebrew/opt/fzf/shell/key-bindings.zsh

zinit light Aloxaf/fzf-tab
zinit snippet OMZL::git.zsh
zinit snippet OMZP::git
zinit snippet OMZP::sudo
zinit snippet OMZP::aws
zinit snippet OMZP::kubectl

bindkey -v
KEYTIMEOUT=10
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^[w' kill-region
bindkey '^A' beginning-of-line
bindkey '^E' end-of-line
bindkey '^K' kill-line
bindkey '^U' backward-kill-line

HISTSIZE=5000
HISTFILE="$HOME/.zsh_history"
SAVEHIST=$HISTSIZE
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls -G $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls -G $realpath'

alias ls='ls -G'
alias vim='nvim'
alias c='clear'
alias python='python3'
alias diary='nvim ~/Documents/diary.md'

source "$HOME/.config/zsh/secrets.zsh"

export NVM_DIR="$HOME/.nvm"
load-nvm() {
  [[ -s /opt/homebrew/opt/nvm/nvm.sh ]] || {
    print -u2 'NVM is required but /opt/homebrew/opt/nvm/nvm.sh is missing'
    return 1
  }
  [[ -s /opt/homebrew/opt/nvm/etc/bash_completion.d/nvm ]] || {
    print -u2 'NVM completion is required but missing'
    return 1
  }
  unset -f nvm node npm npx corepack load-nvm
  source /opt/homebrew/opt/nvm/nvm.sh
  source /opt/homebrew/opt/nvm/etc/bash_completion.d/nvm
}
nvm() { load-nvm || return; nvm "$@"; }
node() { load-nvm || return; node "$@"; }
npm() { load-nvm || return; npm "$@"; }
npx() { load-nvm || return; npx "$@"; }
corepack() { load-nvm || return; corepack "$@"; }

export BUN_INSTALL="$HOME/.bun"

export GOPATH="$HOME/go"
export GOBIN="$GOPATH/bin"
export PNPM_HOME="$HOME/Library/pnpm"
export PATH="$BUN_INSTALL/bin:$HOME/.opencode/bin:$HOME/.local/bin:/usr/local/go/bin:$GOBIN:$PNPM_HOME/bin:$PATH"

ZSH_AUTOSUGGEST_STRATEGY=(history completion)
zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-syntax-highlighting

eval "$(zoxide init zsh)"
eval "$(starship init zsh)"
