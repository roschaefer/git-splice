# check_drawing after a `git mv` of the splice, against the
# moved-with-unpushed-commits drawing: U(x) of a commit from before the
# move is read from the folder the splice had then.

setup() {
  load 'helpers/fixtures'
  load '../check-drawing/check-drawing'
  hermetic_git_config
  load 'scenarios/up-to-date/push-ahead/moved-with-unpushed-commits/setup'
  PATH="$BATS_TEST_DIRNAME/..:$PATH"
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  scenario_moved_with_unpushed_commits "$monorepo" "$upstream"
  cd "$monorepo"
  git mv vendor/a libs/a
  git commit -q -m "reorganize folders"
  drawing="$BATS_TEST_TMPDIR/moved-with-unpushed-commits.drawio"
  xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' \
    "$BATS_TEST_DIRNAME/scenarios/up-to-date/push-ahead/moved-with-unpushed-commits/moved-with-unpushed-commits.drawio.svg" >"$drawing" 2>/dev/null
  revs=(a=HEAD~2 b=HEAD~1 m=HEAD k=refs/splices/upstream/main)
}

edit_drawing() {
  xmlstarlet ed -L "$@" "$drawing"
}

@test "drawing moved: U(B) of a boundary from before the move is read under the old folder" {
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 0 ]
  [ "$output" = "ok   moved-with-unpushed-commits.drawio: 5 commits, 7 arrows, 4 boxes, 1 lanes" ]
}

@test "drawing moved: U(x) of a commit from before the move is read under the old folder" {
  edit_drawing -u '//mxCell[@id="box1"]/@value' -v 'T = U(a)'
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 0 ]
}

@test "drawing moved: U(x) of a commit on a branch forked after the move is read under the new folder" {
  git switch -q -c side
  echo "side" >>libs/a/file.txt
  git commit -q -am "side change"
  git switch -q main
  # s, outside the lane, as m's child.
  sed -i 's#</root>#<mxCell id="s" parent="1" vertex="1" value="s" style="ellipse;aspect=fixed;"><mxGeometry x="400" y="0" width="70" height="70" as="geometry" /></mxCell><mxCell id="e_s" parent="1" edge="1" source="m" target="s"><mxGeometry relative="1" as="geometry" /></mxCell></root>#' "$drawing"
  edit_drawing -u '//mxCell[@id="box1"]/@value' -v 'T = U(s)'
  run check_drawing "$drawing" "${revs[@]}" s=side
  [ "$status" -eq 0 ]
}

@test "drawing moved: U(x) of a commit on a branch that moved the splice on its own is read under that branch's folder" {
  git switch -q -c side HEAD~1
  mkdir other
  git mv vendor/a other/a
  git commit -q -m "side move"
  git switch -q main
  # s, outside the lane, as b's child.
  sed -i 's#</root>#<mxCell id="s" parent="1" vertex="1" value="s" style="ellipse;aspect=fixed;"><mxGeometry x="400" y="0" width="70" height="70" as="geometry" /></mxCell><mxCell id="e_s" parent="1" edge="1" source="b" target="s"><mxGeometry relative="1" as="geometry" /></mxCell></root>#' "$drawing"
  edit_drawing -u '//mxCell[@id="box1"]/@value' -v 'T = U(s)'
  run check_drawing "$drawing" "${revs[@]}" s=side
  [ "$status" -eq 0 ]
}

@test "drawing moved: a commit an earlier splice at the old folder recorded isn't this splice's" {
  # vendor/a/ held a splice of another upstream before this one was
  # cloned there.
  rm -rf "$monorepo" "$upstream"
  local other="$BATS_TEST_TMPDIR/other.git" x
  make_bare_repo "$other"
  seed_bare_repo "$other" "other seed"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$other" vendor/a
  cd "$monorepo"
  x="$(git config --file vendor/a/.splice splice.commit)"
  git rm -q -r vendor/a
  git commit -q -m "drop vendor/a"
  add_splice "$monorepo" "$upstream" vendor/a
  commit_local "$monorepo" vendor/a "local change"
  mkdir libs
  git mv vendor/a libs/a
  git commit -q -m "reorganize folders"
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 0 ]
  # x, the other upstream's commit, in the lane.
  sed -i 's#</root>#<mxCell id="x" parent="1" vertex="1" value="x" style="ellipse;aspect=fixed;"><mxGeometry x="850" y="208" width="70" height="70" as="geometry" /></mxCell></root>#' "$drawing"
  run check_drawing "$drawing" "${revs[@]}" x="$x"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   x is in the lane libs/a/, but isn't in that splice's upstream history or R" ]
}

@test "drawing moved: U(x) of a commit on a merged branch that moved the splice on its own is read under that branch's folder" {
  git switch -q -c side HEAD~1
  mkdir other
  git mv vendor/a other/a
  git commit -q -m "side move"
  git switch -q main
  git merge -q -s ours --no-edit side
  # s as b's child, and the merge M of m and s, now H.
  sed -i 's#</root>#<mxCell id="s" parent="1" vertex="1" value="s" style="ellipse;aspect=fixed;"><mxGeometry x="400" y="74" width="70" height="70" as="geometry" /></mxCell><mxCell id="e_s" parent="1" edge="1" source="b" target="s"><mxGeometry relative="1" as="geometry" /></mxCell><mxCell id="M" parent="1" vertex="1" value="M" style="ellipse;aspect=fixed;"><mxGeometry x="229" y="0" width="70" height="70" as="geometry" /></mxCell><mxCell id="e_mM" parent="1" edge="1" source="m" target="M"><mxGeometry relative="1" as="geometry" /></mxCell><mxCell id="e_sM" parent="1" edge="1" source="s" target="M"><mxGeometry relative="1" as="geometry" /></mxCell></root>#' "$drawing"
  edit_drawing -u '//mxCell[@source="box0"]/@target' -v M -u '//mxCell[@id="box1"]/@value' -v 'T = U(s)'
  run check_drawing "$drawing" a=HEAD~3 b=HEAD~2 m=HEAD~1 M=HEAD k=refs/splices/upstream/main s=side
  [ "$status" -eq 0 ]
}

@test "drawing moved: U(x) of a commit from before the splice was copied from a mirror isn't the mirror's" {
  # vendor/a/ is a copy of the mirror vendor/orig/, so both have one id.
  rm -rf "$monorepo" "$upstream"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" vendor/orig
  cd "$monorepo"
  cp -r vendor/orig vendor/a
  git add vendor/a
  git commit -q -m "copy vendor/orig"
  commit_local "$monorepo" vendor/a "local change"
  mkdir libs
  git mv vendor/a libs/a
  git commit -q -m "reorganize folders"
  # With two splices, B outside every lane can't say whose it is.
  edit_drawing -d '//mxCell[@id="box3" or @source="box3"]'
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 0 ]
  # x, the commit that added the mirror, as a's parent.
  sed -i 's#</root>#<mxCell id="x" parent="1" vertex="1" value="x" style="ellipse;aspect=fixed;"><mxGeometry x="229" y="476" width="70" height="70" as="geometry" /></mxCell><mxCell id="e_x" parent="1" edge="1" source="x" target="a"><mxGeometry relative="1" as="geometry" /></mxCell></root>#' "$drawing"
  edit_drawing -u '//mxCell[@id="box1"]/@value' -v 'T = U(x)'
  run check_drawing "$drawing" "${revs[@]}" x=HEAD~3
  [ "$status" -eq 1 ]
  [ "$output" = "!!   U(x) points at k, but there's no U(x)" ]
}
