# Prints the arguments git-subtrees receives when a command line is
# completed and run in a real interactive bash, as "[arg][arg]...".
#
#   zsh test/helpers/bash-complete.zsh <completion-file> <line>
#
# Starts the bash on PATH in a pseudo-terminal (zsh/zpty), sources
# <completion-file>, replaces git-subtrees with a function printing its
# arguments, types <line>, presses Tab once, then Enter. Unlike calling the
# completion function with hand-made COMP_WORDS, this covers how bash
# splits the line into words, how readline inserts the completion, and what
# the shell does with the completed line.

zmodload zsh/zpty

# Reads from the pty until the output contains $1, or gives up after about
# 5s. Appends to $output.
read_until() {
  local needle=$1 chunk tries=0
  while ((tries++ < 50)); do
    while zpty -r -t b chunk; do output+=$chunk; done
    [[ $output == *"$needle"* ]] && return 0
    sleep 0.1
  done
  return 1
}

main() {
  local comp_file=$1 line=$2 output="" args
  zpty b "TERM=dumb PS1='> ' bash --norc --noprofile -i"
  # Input typed before bash's first prompt can get lost.
  read_until '> ' || { zpty -d b; return 1; }
  zpty -w b "bind 'set enable-bracketed-paste off' 2>/dev/null"
  zpty -w b "source '$comp_file'"
  # The markers are spelled differently in the typed commands than in their
  # output, so a terminal echoing the input can't match them early.
  zpty -w b "git-subtrees() { printf '__AR''GS__'; printf '[%s]' \"\$@\"; printf '__E''ND__\\n'; }"
  zpty -w b "echo __READY\"\"__"
  read_until __READY__ || { zpty -d b; return 1; }

  output=""
  zpty -n -w b "$line"$'\t'
  sleep 0.5
  zpty -n -w b $'\r'
  read_until __END__
  zpty -d b

  args=${output##*__ARGS__}
  [[ $output == *__ARGS__* ]] && print -r -- "${args%%__END__*}"
}

main "$@"
