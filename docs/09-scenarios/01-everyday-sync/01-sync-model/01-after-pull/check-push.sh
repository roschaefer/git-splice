#!/bin/sh
set -eu

test "$GIT_SPLICE_PATH" = lib
git cat-file -e "$GIT_SPLICE_COMMIT^{commit}"
case "$GIT_SPLICE_EVENT" in
  after-rebuild)
    printf 'Prepared, before publication:\n'
    "$CHECK_DRAWING_TOOL" "$EXEC_DRAWINGS/after-pull.drawio.svg"
    ;;
  after-push)
    printf 'Published:\n'
    "$CHECK_DRAWING_TOOL" "$EXEC_DRAWINGS/01-pushed/pushed.drawio.svg"
    ;;
  *) exit 1 ;;
esac
