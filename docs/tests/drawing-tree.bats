# check_drawing on a splice tree, a drawing whose root text is styled
# tree=1, against the recursive pull scenario's drawings.

setup() {
  load 'helpers/fixtures'
  load '../../check-drawing/check-drawing'
  hermetic_git_config
  load '../09-scenarios/05-nested-splices/05-recursive-pull/setup'
  PATH="$(dirname "$ENTRYPOINT"):$PATH"
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream"
  local x i=0
  for x in a b c d e; do
    export "GIT_CONFIG_KEY_$i=url.$upstream-$x.git.insteadOf" "GIT_CONFIG_VALUE_$i=https://git.example.com/$x.git"
    i=$((i + 1))
  done
  export GIT_CONFIG_COUNT=$i
  scenario_recursive_pull "$monorepo" "$upstream"
  cd "$monorepo"
  echo "a in the monorepo" >>vendor/a/file.txt
  echo "b in the monorepo" >>vendor/a/b/notes.txt
  git add vendor/a
  git commit -q -m "m1: a and b in the monorepo"
  drawings="$BATS_TEST_DIRNAME/../09-scenarios/05-nested-splices/05-recursive-pull"
  drawing="$BATS_TEST_TMPDIR/tree-before.drawio"
  xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' \
    "$drawings/tree-before.drawio.svg" >"$drawing" 2>/dev/null
}

edit_drawing() {
  xmlstarlet ed -L "$@" "$drawing"
}

@test "drawing tree: the committed one matches its scenario" {
  run check_drawing "$drawing"
  [ "$status" -eq 0 ]
  [ "$output" = "ok   tree-before.drawio: a tree of 5 rows" ]
}

@test "drawing tree: a synced commit the parent doesn't record" {
  edit_drawing -u '//mxCell[@value="c1"]/@value' -v d1
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   d1 is vendor/a/b/c/'s synced commit, but the code says c1 ("* ]]
}

@test "drawing tree: a splice without a row" {
  local text
  text="$(xmlstarlet sel -t -v '//mxCell[@value="d/"]/@id' "$drawing")"
  edit_drawing -d "//mxCell[@id=\"$text\"]"
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a/d is a splice of the monorepo, but has no row: draw one, so the tree shows every splice"* ]]
}

@test "drawing tree: R of a splice without commits of its own" {
  git reset -q --hard HEAD~1
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a/ has no commits of its own, R is its synced commit: drop m1'"* ]]
}

@test "drawing tree: a splice with commits of its own, without R" {
  commit_local "$monorepo" vendor/a/d "d local"
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a/d/ has commits of its own: draw R, d local ("* ]]
}

@test "drawing tree: an edge from the synced commit, where the parent has R" {
  local synced r
  synced="$(xmlstarlet sel -t -v '//mxCell[@value="a1"]/@id' "$drawing")"
  r="$(xmlstarlet sel -t -v "//mxCell[@edge=\"1\"][@source=\"$synced\"]/@target" "$drawing")"
  edit_drawing -u "//mxCell[@edge=\"1\"][@source=\"$r\"][contains(@style,'endArrow=none')][1]/@source" -v "$synced"
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"hangs from a1, but its parent's head is m1': draw the edge from the head"* ]]
}
