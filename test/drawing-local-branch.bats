# check_drawing with a dashed box: a branch of the monorepo with a
# splice's commits that no upstream has, e.g. one checked out in a worktree
# of the rebuild, drawn in the splice's lane with its commits dashed.

setup() {
  load 'helpers/fixtures'
  load '../check-drawing/check-drawing'
  hermetic_git_config
  load 'scenarios/01-everyday-sync/02-up-to-date/setup'
  PATH="$(dirname "$ENTRYPOINT"):$PATH"
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  scenario_up_to_date "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "n"
  cd "$monorepo"
  git splice fetch vendor/a >/dev/null 2>&1
  echo b >vendor/a/local.txt && git add vendor/a/local.txt && git commit -q -m "b"
  git worktree add -q -b work-on-a "$BATS_TEST_TMPDIR/a-work" "$(git splice rebuild vendor/a)"
  git -C "$BATS_TEST_TMPDIR/a-work" pull -q --no-rebase --no-edit "$upstream" main
  drawing="$BATS_TEST_TMPDIR/worktree.drawio"
  worktree_drawing
}

# The monorepo's a and b, H at b; in the lane, k, the upstream's n, T, and
# the worktree's branch: b' on k, and w, the pull's merge of b' and n.
worktree_drawing() {
  local dashed="ellipse;dashed=1;" box="rounded=1;"
  cat >"$drawing" <<XML
<mxfile><diagram id="d"><mxGraphModel><root><mxCell id="0" /><mxCell id="1" parent="0" />
<mxCell id="lane" parent="1" vertex="1" style="rounded=1;fillColor=none;" value="vendor/a/"><mxGeometry x="150" y="-110" width="400" height="440" as="geometry" /></mxCell>
<mxCell id="a" parent="1" vertex="1" style="ellipse;" value="a"><mxGeometry x="60" y="250" width="54" height="54" as="geometry" /></mxCell>
<mxCell id="b" parent="1" vertex="1" style="ellipse;" value="b"><mxGeometry x="60" y="150" width="54" height="54" as="geometry" /></mxCell>
<mxCell id="refH" parent="1" vertex="1" style="$box" value="H"><mxGeometry x="0" y="160" width="40" height="34" as="geometry" /></mxCell>
<mxCell id="k" parent="1" vertex="1" style="ellipse;" value="k"><mxGeometry x="290" y="250" width="54" height="54" as="geometry" /></mxCell>
<mxCell id="n" parent="1" vertex="1" style="ellipse;" value="n"><mxGeometry x="240" y="150" width="54" height="54" as="geometry" /></mxCell>
<mxCell id="refT" parent="1" vertex="1" style="$box" value="T"><mxGeometry x="170" y="160" width="40" height="34" as="geometry" /></mxCell>
<mxCell id="b_" parent="1" vertex="1" style="$dashed" value="b'"><mxGeometry x="350" y="150" width="54" height="54" as="geometry" /></mxCell>
<mxCell id="w" parent="1" vertex="1" style="$dashed" value="w"><mxGeometry x="300" y="50" width="54" height="54" as="geometry" /></mxCell>
<mxCell id="refW" parent="1" vertex="1" style="${WORK_BOX_STYLE:-rounded=1;dashed=1;}" value="${WORK_BOX:-work-on-a}"><mxGeometry x="${WORK_BOX_X:-400}" y="60" width="110" height="34" as="geometry" /></mxCell>
<mxCell id="e0" parent="1" edge="1" source="a" target="b" style=""><mxGeometry relative="1" as="geometry" /></mxCell>
<mxCell id="e1" parent="1" edge="1" source="refH" target="b" style=""><mxGeometry relative="1" as="geometry" /></mxCell>
<mxCell id="e2" parent="1" edge="1" source="k" target="n" style=""><mxGeometry relative="1" as="geometry" /></mxCell>
<mxCell id="e3" parent="1" edge="1" source="refT" target="n" style=""><mxGeometry relative="1" as="geometry" /></mxCell>
<mxCell id="e4" parent="1" edge="1" source="k" target="b_" style="dashed=1;"><mxGeometry relative="1" as="geometry" /></mxCell>
<mxCell id="e5" parent="1" edge="1" source="b_" target="w" style="dashed=1;"><mxGeometry relative="1" as="geometry" /></mxCell>
<mxCell id="e6" parent="1" edge="1" source="n" target="w" style="dashed=1;"><mxGeometry relative="1" as="geometry" /></mxCell>
<mxCell id="e7" parent="1" edge="1" source="refW" target="w" style=""><mxGeometry relative="1" as="geometry" /></mxCell>
</root></mxGraphModel></diagram></mxfile>
XML
}

check() {
  run check_drawing "$drawing" a=HEAD~1 k="$(git config --file vendor/a/.splice splice.commit)" w=work-on-a
}

@test "drawing local branch: a dashed box names a branch of the monorepo, whose commits in the lane are dashed" {
  check
  [ "$status" -eq 0 ]
  [ "$output" = "ok   worktree.drawio: 6 commits, 8 arrows, 3 boxes, 1 lanes" ]
}

@test "drawing local branch: a solid box naming a branch of the monorepo in a lane is to be dashed" {
  WORK_BOX_STYLE="rounded=1;" worktree_drawing
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   work-on-a is a branch of the monorepo, which the upstream doesn't have: dash the box"* ]]
}

@test "drawing local branch: its commits are dashed, as no upstream has them" {
  sed -i 's|id="b_" parent="1" vertex="1" style="ellipse;dashed=1;"|id="b_" parent="1" vertex="1" style="ellipse;"|' "$drawing"
  check
  [ "$status" -eq 1 ]
  [ "$output" = "!!   b' is solid, but no upstream branch has it: dash it" ]
}

@test "drawing local branch: a dashed box names a branch the monorepo has" {
  git worktree remove "$BATS_TEST_TMPDIR/a-work"
  git branch -q -m work-on-a renamed
  run check_drawing "$drawing" a=HEAD~1 k="$(git config --file vendor/a/.splice splice.commit)" w=renamed
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   work-on-a is dashed, but the monorepo has no branch work-on-a: a dashed box names a branch of the monorepo"* ]]
}

@test "drawing local branch: a dashed box stays in the lane of the splice whose commits it has" {
  WORK_BOX_X=-300 worktree_drawing
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   work-on-a is dashed, but outside every lane: a dashed box names a branch of the monorepo with a splice's commits, so draw it in that splice's lane"* ]]
}

@test "drawing local branch: only a branch box can be dashed" {
  sed -i 's|id="refT" parent="1" vertex="1" style="rounded=1;"|id="refT" parent="1" vertex="1" style="rounded=1;dashed=1;"|' "$drawing"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   T is dashed, but only a branch of the monorepo is: draw it solid"* ]]
}

@test "drawing local branch: its commits stay in the lane, not outside every lane like the monorepo's" {
  sed -i 's|id="b_" parent="1" vertex="1" style="ellipse;dashed=1;" value="b'"'"'"><mxGeometry x="350"|id="b_" parent="1" vertex="1" style="ellipse;dashed=1;" value="b'"'"'"><mxGeometry x="-200"|' "$drawing"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   b' is on the dashed branch of the lane vendor/a/, but outside every lane: draw it in that lane"* ]]
}

@test "drawing local branch: a solid box at a commit only the monorepo's branch has is to be dashed, also where the upstream has a branch of that name" {
  git worktree remove "$BATS_TEST_TMPDIR/a-work"
  git branch -q -m work-on-a main-work
  git update-ref "refs/splices/$(git splice key vendor/a)/heads/main-work" "refs/splices/$(git splice key vendor/a)/heads/main"
  WORK_BOX=main-work WORK_BOX_STYLE="rounded=1;" worktree_drawing
  run check_drawing "$drawing" a=HEAD~1 k="$(git config --file vendor/a/.splice splice.commit)" w=main-work
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   main-work is a branch of the monorepo, which the upstream doesn't have: dash the box"* ]]
}
