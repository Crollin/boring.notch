# Boring Notch : signale la fin des commandes longues. À sourcer depuis ~/.zshrc :
#   source ~/Projects/boring.notch/scripts/cmd-hook.zsh
# Seuil : BN_MIN_SECONDS (30 par défaut). Échoue en silence si l'app est fermée ; l'envoi part en arrière-plan.

zmodload zsh/datetime

_bn_preexec() { _bn_cmd=$1; _bn_start=$EPOCHREALTIME }

_bn_precmd() {
  local code=$? sock="$HOME/Library/Containers/theboringteam.boringnotch/Data/.bn.sock"
  [[ -n $_bn_start ]] || return 0
  local d=$(( EPOCHREALTIME - _bn_start ))
  unset _bn_start
  (( d >= ${BN_MIN_SECONDS:-30} )) && [[ -S $sock ]] || return 0
  # Échappement JSON minimal ; un caractère de contrôle restant fait juste ignorer l'événement.
  local cmd=${_bn_cmd//\\/\\\\}
  cmd=${cmd//\"/\\\"}
  cmd=${cmd//$'\n'/ }
  cmd=${cmd//$'\t'/ }
  printf '{"kind":"command","source":"zsh","app":"%s","payload":{"command":"%s","exit_code":%d,"duration":%.0f}}' \
    "$__CFBundleIdentifier" "${cmd[1,120]}" $code $d | nc -U -w 1 "$sock" >/dev/null 2>&1 &!
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _bn_preexec
add-zsh-hook precmd _bn_precmd
