# shellcheck shell=bash
# Sourced by a hidden scrut block of the repository's README.md, after
# test/readme/scrut-setup.sh and the clone: makes the commits the README's
# diagram shows. In the monorepo, two of four commits touch vendor/lib/;
# the library gets two commits of its own since the clone. Then fetches,
# so 'git splice status' sees both sides.

{
  echo "helper" >>app/main.txt &&
    echo "helper" >>vendor/lib/src/parse.txt &&
    git commit -q -am "rename helper in app and lib" &&
    echo "dependencies" >>app/main.txt &&
    git commit -q -am "app: bump dependencies" &&
    echo "options" >>vendor/lib/src/parse.txt &&
    git commit -q -am "fix parse() options" &&
    echo "parse()" >>app/main.txt &&
    git commit -q -am "app: call parse()" &&
    seed_bare_repo "$PWD/../github.com/x/lib.git" "docs: explain parse()" main README.md &&
    seed_bare_repo "$PWD/../github.com/x/lib.git" "release 1.3" main src/version.txt &&
    git splice fetch vendor/lib
} >/dev/null 2>&1 || return
