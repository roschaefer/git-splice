# check_drawing after a `git mv` of a splice whose upstream rewrote its
# history, against the upstream-rewritten-equal-tree drawing: a commit
# only an older .splice records, under the folder the splice had then,
# is still the splice's.

setup() {
  load 'helpers/fixtures'
  load '../check-drawing/check-drawing'
  hermetic_git_config
  load 'scenarios/06-rewritten-history/02-upstream-rewritten-equal-tree/setup'
  PATH="$BATS_TEST_DIRNAME/..:$PATH"
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  scenario_upstream_rewritten_equal_tree "$monorepo" "$upstream"
  cd "$monorepo"
  r="$(git config --file vendor/a/.splice splice.commit)"
  git splice merge vendor/a >/dev/null
  mkdir libs
  git mv vendor/a libs/a
  git commit -q -m "reorganize folders"
  drawing="$BATS_TEST_TMPDIR/upstream-rewritten-equal-tree.drawio"
  xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' \
    "$BATS_TEST_DIRNAME/scenarios/06-rewritten-history/02-upstream-rewritten-equal-tree/upstream-rewritten-equal-tree.drawio.svg" >"$drawing" 2>/dev/null
  # The boxes on a no longer hold after the merge and the move.
  xmlstarlet ed -L -d '//mxCell[@id="box0" or @id="box1" or @source="box0" or @source="box1"]' \
    -u '//mxCell[@id="lane"]/@value' -v libs/a/ "$drawing"
}

@test "drawing moved: a commit only a .splice from before the move records is the splice's" {
  run check_drawing "$drawing" a=HEAD~2 k="$r~1" r="$r" w=refs/splices/upstream/heads/main
  [ "$status" -eq 0 ]
}
