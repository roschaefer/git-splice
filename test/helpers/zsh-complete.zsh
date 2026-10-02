# Prints the candidates zsh lists for a command line, one per line.
#
#   zsh test/helpers/zsh-complete.zsh <completion-file> <line>
#
# Completion widgets only run inside a live line editor, so this starts an
# interactive zsh in a pseudo-terminal (zsh/zpty), installs <completion-file>
# as _git-splice, types <line> and asks for the list of choices. The
# candidates are what zsh prints between the typed line and its redraw.

zmodload zsh/zpty

# Reads from the pty until the output contains $1 at least $2 times, or
# gives up after about 5s. Appends to $output.
read_until() {
  local needle=$1 count=$2 chunk rest found tries=0
  while ((tries++ < 50)); do
    while zpty -r -t z chunk; do output+=$chunk; done
    rest=$output
    found=0
    while [[ $rest == *"$needle"* ]]; do
      rest=${rest#*"$needle"}
      ((found++))
    done
    ((found >= count)) && return 0
    sleep 0.1
  done
  return 1
}

main() {
  setopt local_options extended_glob
  local comp_file=$1 line=$2 rc_dir output="" candidates
  rc_dir=$(mktemp -d)
  mkdir "$rc_dir/fpath"
  cp "$comp_file" "$rc_dir/fpath/_git-splice"
  cat >"$rc_dir/.zshrc" <<RC
PS1='> '
setopt no_beep
fpath=($rc_dir/fpath \$fpath)
autoload -U compinit && compinit -u -D
zstyle ':completion:*' list-prompt ''
LISTMAX=0
bindkey '^X' list-choices
print __READY__
RC

  zpty z "TERM=dumb ZDOTDIR=$rc_dir zsh -i"
  read_until __READY__ 1
  output=""
  zpty -n -w z "$line"$'\C-x'
  # No candidates means no list and no redraw, so a timeout is fine here.
  read_until "$line" 2
  zpty -d z
  rm -rf "$rc_dir"

  # Drop carriage returns, bells and terminal escape sequences, then keep what zsh
  # printed between the typed line and its redraw.
  output=${output//[$'\r\a']/}
  output=${output//$'\e'\[[0-9;?]#[[:alpha:]]/}
  candidates=${output#*"$line"}
  candidates=${candidates%%"$line"*}
  local l
  for l in ${(f)candidates}; do
    l=${${l##[[:space:]]#}%%[[:space:]]#}
    [[ -n $l && $l != '>' ]] && print -r -- "$l"
  done
}

main "$@"
