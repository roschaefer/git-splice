# check_drawing, against the after-pull drawing and its scenario: the
# drawing as committed passes, and each kind of drift fails with a message
# that says what to change.

setup() {
  load 'helpers/fixtures'
  load '../check-drawing/check-drawing'
  hermetic_git_config
  load 'scenarios/sync-model/after-pull/setup'
  PATH="$BATS_TEST_DIRNAME/..:$PATH"
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  scenario_after_pull "$monorepo" "$upstream"
  drawing="$BATS_TEST_TMPDIR/after-pull.drawio"
  xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' \
    "$BATS_TEST_DIRNAME/scenarios/sync-model/after-pull/after-pull.drawio.svg" >"$drawing" 2>/dev/null
  cd "$monorepo"
}

# Applies xmlstarlet ed options to the drawing.
edit_drawing() {
  xmlstarlet ed -L "$@" "$drawing"
}

@test "drawing: the committed one matches its scenario" {
  run check_drawing "$BATS_TEST_DIRNAME/scenarios/sync-model/after-pull/after-pull.drawio.svg" a=HEAD~4 e=HEAD
  [ "$status" -eq 0 ]
  [ "$output" = "ok   after-pull.drawio.svg: 12 commits, 17 arrows, 6 boxes, 2 frames, 1 lanes" ]
}

@test "drawing: a box pointing at the wrong commit names the right one" {
  edit_drawing -u '//mxCell[@source="refR"]/@target' -v d_
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   R points at d', the code says e'" ]
}

@test "drawing: a solid arrow into a rebuilt commit is to be dashed" {
  edit_drawing -u '//mxCell[@source="n" and @target="e_"]/@style' -v 'endArrow=block;endFill=1;'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   n -> e' is solid, but no upstream branch has e': dash it" ]
}

@test "drawing: a solid rebuilt commit is to be dashed" {
  edit_drawing -u '//mxCell[@id="b_"]/@style' -v 'ellipse;aspect=fixed;'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   b' is solid, but no upstream branch has it: dash it" ]
}

@test "drawing: a box sits on the side of what it names" {
  # box, where it moves (in: into the lane path/, out: outside it), and
  # how the check's output starts.
  local box where expected x y failed=""
  cp "$drawing" "$BATS_TEST_TMPDIR/committed.drawio"
  while IFS='|' read -r box where expected; do
    cp "$BATS_TEST_TMPDIR/committed.drawio" "$drawing"
    if [[ "$where" == in ]]; then x=950 y=640; else x=20 y=380; fi
    edit_drawing -u "//mxCell[@id=\"$box\"]/mxGeometry/@x" -v "$x" -u "//mxCell[@id=\"$box\"]/mxGeometry/@y" -v "$y"
    run check_drawing "$drawing" a=HEAD~4 e=HEAD
    [[ "${lines[0]}" == "$expected"* ]] || failed+=$'\n'"$box $where: ${lines[0]}"
  done <<'EOF'
refH|in|!!   H names a monorepo commit: draw it outside every lane
refB|in|!!   B names a monorepo commit: draw it outside every lane
refT|out|!!   T names an upstream commit: draw it in the lane of its splice
refR|out|!!   R names an upstream commit: draw it in the lane of its splice
refU|in|ok
refS|in|ok
refT|in|ok
EOF
  [ -z "$failed" ] || {
    echo "$failed"
    false
  }
}

git_names=(--alias HEAD=H --alias BOUNDARY=B --alias OURS=R --alias THEIRS=T --alias 'BASE=merge-base(R,T)')

@test "drawing: aliases let boxes use Git's names for a three-way merge" {
  edit_drawing -u '//mxCell[@id="refR"]/@value' -v OURS \
    -u '//mxCell[@id="refT"]/@value' -v 'THEIRS = BASE' \
    -u '//mxCell[@id="refH"]/@value' -v HEAD \
    -u '//mxCell[@id="refB"]/@value' -v BOUNDARY \
    -u '//mxCell[@id="refS"]/@value' -v 'U(BOUNDARY)' \
    -u '//mxCell[@id="refU"]/@value' -v 'U(HEAD)'
  run check_drawing "$drawing" "${git_names[@]}" a=HEAD~4 e=HEAD
  [ "$status" -eq 0 ]
}

@test "drawing: without an alias, a name like OURS is an upstream branch" {
  edit_drawing -u '//mxCell[@id="refR"]/@value' -v OURS
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   OURS points at e', but there's no OURS" ]
}

@test "drawing: merge-base(R,T) is where R and T meet" {
  edit_drawing -u '//mxCell[@id="refR"]/@value' -v 'merge-base(R,T)'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   merge-base(R,T) points at e', the code says n" ]
}

@test "drawing: a missing parent arrow is named" {
  edit_drawing -d '//mxCell[@source="d_" and @target="e_"]'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   no arrow d' -> e', though d' is a parent of e'" ]
}

@test "drawing: an arrow from a commit that isn't the parent" {
  edit_drawing -u '//mxCell[@source="c" and @target="d"]/@source' -v b
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   b -> d: b isn't a parent of d" ]
  [ "${lines[1]}" = "!!   no arrow c -> d, though c is a parent of d" ]
}

@test "drawing: a frame named after another commit than the one it holds" {
  edit_drawing -u '//mxCell[@id="fu"]/@value' -v 'd:path/.splice'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = '!!   the frame "d:path/.splice" holds e, not d' ]
}

@test "drawing: a box U(X) on a commit X's .splice doesn't record" {
  edit_drawing -u '//mxCell[@id="refU"]/@value' -v 'U(a)'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   U(a) points at n, the code says k" ]
}

@test "drawing: a box U(X) for a commit that isn't drawn" {
  edit_drawing -u '//mxCell[@id="refU"]/@value' -v 'U(z)'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   U(z) points at n, but no commit z is drawn" ]
}

@test "drawing: an arrow from a commit into a box is to be reversed" {
  edit_drawing -u '//mxCell[@source="refR"]/@source' -v e_ -u '//mxCell[@source="e_" and @target="e_"]/@target' -v refR
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   an arrow from e' points at the box R: draw it from the box to its commit" ]
  [ "${lines[1]}" = "!!   R has 0 arrows, not one: draw one from the box to its commit" ]
}

@test "drawing: U(H) is what HEAD records, whatever the working tree's .splice says" {
  git config --file vendor/a/.splice splice.commit "$(git rev-parse HEAD)"
  run check_drawing "$BATS_TEST_DIRNAME/scenarios/sync-model/after-pull/after-pull.drawio.svg" a=HEAD~4 e=HEAD
  [ "$status" -eq 0 ]
}

@test "drawing: a box without an arrow points nowhere" {
  edit_drawing -d '//mxCell[@source="refT"]'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   T has 0 arrows, not one: draw one from the box to its commit" ]
}

@test "drawing: an arrow not attached to a shape" {
  edit_drawing -d '//mxCell[@source="refT"]/@target'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == "!!   an arrow (e7) isn't attached at both ends: drag its ends onto shapes" ]]
}

@test "drawing: an arrow whose start isn't attached" {
  edit_drawing -d '//mxCell[@source="refT"]/@source'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   an arrow (e7) isn't attached at both ends: drag its ends onto shapes" ]
  [[ "$output" != *"bad array subscript"* ]]
}

@test "drawing: a label that's no commit's subject" {
  edit_drawing -u '//mxCell[@id="c"]/@value' -v x
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   x: no such commit" ]
}

@test "drawing: a compressed diagram asks to be saved uncompressed" {
  printf '<mxfile><diagram id="x">7VhNb5tAEP01HC0Z</diagram></mxfile>\n' >"$drawing"
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "$output" = "!!   after-pull.drawio: no diagram inside, or a compressed one: save it with File > Properties > Compressed off" ]
}

@test "drawing: a solid commit T lacks needs a box for the branch that has it" {
  load 'scenarios/up-to-date/squash-merged-pull/setup'
  scenario_squash_merged_pull "$BATS_TEST_TMPDIR/squash" "$BATS_TEST_TMPDIR/squash-upstream.git"
  cd "$BATS_TEST_TMPDIR/squash"
  xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' \
    "$BATS_TEST_DIRNAME/scenarios/up-to-date/squash-merged-pull/squash-merged-pull.drawio.svg" >"$drawing" 2>/dev/null
  edit_drawing -u '//mxCell[@value="U(H) = U(B) = feature"]/@value' -v 'U(H) = U(B)'
  run check_drawing "$drawing" a=HEAD~2 s=HEAD~1 c=HEAD k=refs/splices/squash-upstream/main f=refs/splices/squash-upstream/feature
  [ "$status" -eq 1 ]
  [ "$output" = "!!   f is on an upstream branch, but not T's: draw a box for the branch, e.g. feature" ]
}

@test "drawing: a lane names a splice whose folder Git quotes" {
  load 'scenarios/up-to-date/squash-merged-pull/setup'
  scenario_squash_merged_pull "$BATS_TEST_TMPDIR/squash" "$BATS_TEST_TMPDIR/squash-upstream.git"
  cd "$BATS_TEST_TMPDIR/squash"
  mkdir -p vendor/é && cp vendor/a/.splice vendor/é/ && git add vendor/é && git commit -qm "copy the splice"
  xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' \
    "$BATS_TEST_DIRNAME/scenarios/up-to-date/squash-merged-pull/squash-merged-pull.drawio.svg" >"$drawing" 2>/dev/null
  edit_drawing -u '//mxCell[@value="vendor/a/"]/@value' -v vendor/é/
  run check_drawing "$drawing"
  [[ "$output" != *"isn't a splice of the monorepo"* ]]
}

@test "drawing: a box names an upstream branch with any characters Git allows" {
  load 'scenarios/up-to-date/squash-merged-pull/setup'
  scenario_squash_merged_pull "$BATS_TEST_TMPDIR/squash" "$BATS_TEST_TMPDIR/squash-upstream.git"
  cd "$BATS_TEST_TMPDIR/squash"
  git update-ref refs/splices/squash-upstream/user@feature+1=next refs/splices/squash-upstream/feature
  xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' \
    "$BATS_TEST_DIRNAME/scenarios/up-to-date/squash-merged-pull/squash-merged-pull.drawio.svg" >"$drawing" 2>/dev/null
  edit_drawing -u '//mxCell[@value="U(H) = U(B) = feature"]/@value' -v 'U(H) = U(B) = user@feature+1=next'
  run check_drawing "$drawing" a=HEAD~2 s=HEAD~1 c=HEAD k=refs/splices/squash-upstream/main f=refs/splices/squash-upstream/feature
  [ "$status" -eq 0 ]
}
