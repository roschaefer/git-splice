# check_drawing, against the after-pull drawing and its scenario: the
# drawing as committed passes, and each kind of drift fails with a message
# that says what to change.

setup() {
  load 'helpers/fixtures'
  load '../check-drawing/check-drawing'
  hermetic_git_config
  load 'scenarios/01-everyday-sync/01-sync-model/01-after-pull/setup'
  PATH="$(dirname "$ENTRYPOINT"):$PATH"
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  scenario_after_pull "$monorepo" "$upstream"
  drawing="$BATS_TEST_TMPDIR/after-pull.drawio"
  xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' \
    "$BATS_TEST_DIRNAME/scenarios/01-everyday-sync/01-sync-model/01-after-pull/after-pull.drawio.svg" >"$drawing" 2>/dev/null
  cd "$monorepo"
}

# Applies xmlstarlet ed options to the drawing.
edit_drawing() {
  xmlstarlet ed -L "$@" "$drawing"
}

@test "drawing: the committed one matches its scenario" {
  run check_drawing "$BATS_TEST_DIRNAME/scenarios/01-everyday-sync/01-sync-model/01-after-pull/after-pull.drawio.svg" a=HEAD~4 e=HEAD
  [ "$status" -eq 0 ]
  [ "$output" = "ok   after-pull.drawio.svg: 12 commits, 16 arrows, 5 boxes, 1 lanes" ]
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
  edit_drawing -u '//mxCell[@id="b_"]/@style' -v 'ellipse;aspect=fixed;strokeColor=#E07000;'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   b' is solid, but no upstream branch has it: dash it" ]
}

@test "drawing: a commit the rebuild walks is filled grey only if the legend has a grey sample" {
  edit_drawing -u '//mxCell[@id="c"]/@style' -v 'ellipse;aspect=fixed;fillColor=#E0E0E0;'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   the legend doesn't explain a grey fill: add a sample commit with it, and what it means" ]
  edit_drawing -s '//mxCell[@id="legend"]/..' -t elem -n mxCell \
    -i '//mxCell[not(@id)]' -t attr -n id -v legend_grey \
    -i '//mxCell[@id="legend_grey"]' -t attr -n parent -v legend \
    -i '//mxCell[@id="legend_grey"]' -t attr -n vertex -v 1 \
    -i '//mxCell[@id="legend_grey"]' -t attr -n style -v 'ellipse;fillColor=#E0E0E0;'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   b is a commit the rebuild walks: fill it grey, #E0E0E0"* ]]
  [[ "$output" != *"c is"* ]]
}

@test "drawing: a commit the rebuild walks isn't filled in a color the legend doesn't explain" {
  edit_drawing -u '//mxCell[@id="c"]/@style' -v 'ellipse;aspect=fixed;fillColor=#FFFF00;'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   c is filled #FFFF00, a color the legend doesn't explain: leave it white" ]
}

@test "drawing: a commit the rebuild doesn't walk stays white" {
  edit_drawing -u '//mxCell[@id="a"]/@style' -v 'ellipse;aspect=fixed;fillColor=#E0E0E0;'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   a is filled, but the rebuild doesn't walk it: leave it white"* ]]
}

@test "drawing: a commit R copies is outlined orange" {
  edit_drawing -u '//mxCell[@id="b"]/@style' -v 'ellipse;aspect=fixed;'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   b is a commit R copies: outline it orange, #E07000" ]
}

@test "drawing: R's copy of a commit is outlined orange too" {
  edit_drawing -u '//mxCell[@id="d_"]/@style' -v 'ellipse;aspect=fixed;dashed=1;'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   d' is R's copy of a commit since B: outline it orange, #E07000" ]
}

@test "drawing: R's copy of a commit is labelled after it, with a '" {
  edit_drawing -u '//mxCell[@id="d_"]/@value' -v z
  run check_drawing "$drawing" a=HEAD~4 e=HEAD z="$(splice rebuild lib)^1"
  [ "$status" -eq 1 ]
  [ "$output" = "!!   z is R's copy of d: label it d'" ]
}

@test "drawing: a commit R doesn't copy is outlined black" {
  edit_drawing -u '//mxCell[@id="c"]/@style' -v 'ellipse;aspect=fixed;strokeColor=#E07000;'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   c is outlined in color, but the rebuild doesn't carry it across: outline it black" ]
}

@test "drawing: without a legend, a commit R copies is outlined black, as there's nothing to say why" {
  edit_drawing -d '//mxCell[@id="legend" or @parent="legend"]'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   b is outlined in color, but the drawing has no legend to say why: add one, or outline it black"* ]]
  sed -i 's/strokeColor=#E07000;//g' "$drawing"
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 0 ]
}

@test "drawing: the legend explains each mark a commit has" {
  edit_drawing -d '//mxCell[@parent="legend" and contains(@style, "dashed=1")]'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   the legend doesn't explain a dashed outline: add a sample commit with it, and what it means" ]
}

@test "drawing: the legend explains no mark that no commit has" {
  cat >"$drawing" <<XML
<mxfile><diagram id="d"><mxGraphModel><root><mxCell id="0" /><mxCell id="1" parent="0" />
<mxCell id="a" parent="1" vertex="1" style="ellipse;" value="a"><mxGeometry x="0" y="0" width="70" height="70" as="geometry" /></mxCell>
$(legend_cells prime)
</root></mxGraphModel></diagram></mxfile>
XML
  run check_drawing "$drawing" a=HEAD~4
  [ "$status" -eq 1 ]
  [ "$output" = "!!   the legend explains a ' after a label, which no commit has: drop that sample" ]
}

@test "drawing: black and white set explicitly are colors too" {
  edit_drawing -u '//mxCell[@id="a"]/@style' -v 'ellipse;aspect=fixed;fillColor=#000000;'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   a is filled, but the rebuild doesn't walk it: leave it white" ]
  edit_drawing -u '//mxCell[@id="a"]/@style' -v 'ellipse;aspect=fixed;strokeColor=#FFFFFF;'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   a is outlined in color, but the rebuild doesn't carry it across: outline it black" ]
}

@test "drawing: a transparent outline or fill isn't black or white" {
  edit_drawing -u '//mxCell[@id="a"]/@style' -v 'ellipse;aspect=fixed;strokeColor=none;'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   a is outlined in color, but the rebuild doesn't carry it across: outline it black" ]
  edit_drawing -u '//mxCell[@id="a"]/@style' -v 'ellipse;aspect=fixed;fillColor=none;'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   a is filled, but the rebuild doesn't walk it: leave it white" ]
}

@test "drawing: log.showSignature doesn't hide that R copies a signed commit" {
  command -v ssh-keygen >/dev/null || skip "no ssh-keygen to sign a commit with"
  ssh-keygen -q -t ed25519 -N "" -f "$BATS_TEST_TMPDIR/key"
  git config gpg.format ssh
  git config user.signingKey "$BATS_TEST_TMPDIR/key.pub"
  git commit -q --amend --no-edit -S
  git config log.showSignature true
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 0 ]
}

# The cells of a legend explaining the marks $@: orange, dashed, prime.
legend_cells() {
  local mark row=0 style value
  printf '<mxCell id="legend" parent="1" vertex="1" style="rounded=1;legend=1;" value=""><mxGeometry x="400" y="0" width="300" height="150" as="geometry" /></mxCell>\n'
  for mark in "$@"; do
    value=""
    case "$mark" in
      orange) style="ellipse;strokeColor=#E07000;" ;;
      dashed) style="ellipse;dashed=1;" ;;
      prime) style="ellipse;" value="a'" ;;
    esac
    printf '<mxCell id="legend_%s" parent="legend" vertex="1" style="%s" value="%s"><mxGeometry x="10" y="%d" width="30" height="30" as="geometry" /></mxCell>\n' \
      "$mark" "$style" "$value" $((10 + 40 * row++))
  done
}

# Writes a drawing of two monorepo commits, x and its child y, styled $1
# and $2, with a legend explaining an orange outline.
two_commits_drawing() {
  cat >"$drawing" <<XML
<mxfile><diagram id="d"><mxGraphModel><root><mxCell id="0" /><mxCell id="1" parent="0" />
<mxCell id="x" parent="1" vertex="1" style="$1" value="x"><mxGeometry x="0" y="160" width="70" height="70" as="geometry" /></mxCell>
<mxCell id="y" parent="1" vertex="1" style="$2" value="y"><mxGeometry x="0" y="0" width="70" height="70" as="geometry" /></mxCell>
<mxCell id="e0" parent="1" edge="1" source="x" target="y"><mxGeometry relative="1" as="geometry" /></mxCell>
$(legend_cells orange)
</root></mxGraphModel></diagram></mxfile>
XML
}

@test "drawing: a copy shares the whole message, not only the subject" {
  export GIT_AUTHOR_DATE=2026-01-02T00:00:00Z GIT_COMMITTER_DATE=2026-01-02T00:00:00Z
  echo fix >>lib/file.txt && git add lib/file.txt && git commit -q -m "fix" -m "in lib"
  echo call >>app.txt && git add app.txt && git commit -q -m "fix" -m "in the app"
  two_commits_drawing 'ellipse;strokeColor=#E07000;' 'ellipse;'
  run check_drawing "$drawing" x=HEAD~1 y=HEAD
  [ "$status" -eq 0 ]
}

@test "drawing: right after init, the rebuild walks the mount commit and copies it" {
  load 'scenarios/02-starting-a-splice/04-init-new-upstream/setup'
  scenario_init_new_upstream "$BATS_TEST_TMPDIR/init" "$BATS_TEST_TMPDIR/init.git"
  cd "$BATS_TEST_TMPDIR/init"
  splice init lib/a "$BATS_TEST_TMPDIR/init.git" >/dev/null
  cat >"$drawing" <<XML
<mxfile><diagram id="d"><mxGraphModel><root><mxCell id="0" /><mxCell id="1" parent="0" />
<mxCell id="m" parent="1" vertex="1" style="ellipse;strokeColor=#E07000;" value="m"><mxGeometry x="0" y="0" width="70" height="70" as="geometry" /></mxCell>
<mxCell id="m_" parent="1" vertex="1" style="ellipse;dashed=1;strokeColor=#E07000;" value="m'"><mxGeometry x="160" y="0" width="70" height="70" as="geometry" /></mxCell>
$(legend_cells orange dashed prime)
</root></mxGraphModel></diagram></mxfile>
XML
  run check_drawing "$drawing" m=HEAD
  [ "$status" -eq 0 ]
}

@test "drawing: a box sits with the commit it points at" {
  # box, where it moves (in: into the lane lib/, out: outside it), and
  # how the check's output starts.
  local box where expected x y failed=""
  cp "$drawing" "$BATS_TEST_TMPDIR/committed.drawio"
  while IFS='|' read -r box where expected; do
    cp "$BATS_TEST_TMPDIR/committed.drawio" "$drawing"
    if [[ "$where" == in ]]; then x=900 y=640; else x=20 y=380; fi
    edit_drawing -u "//mxCell[@id=\"$box\"]/mxGeometry/@x" -v "$x" -u "//mxCell[@id=\"$box\"]/mxGeometry/@y" -v "$y"
    run check_drawing "$drawing" a=HEAD~4 e=HEAD
    [[ "${lines[0]}" == "$expected"* ]] || failed+=$'\n'"$box $where: ${lines[0]}"
  done <<'EOF'
refH|in|!!   H points at e, which is outside every lane: draw the box outside every lane too
refB|in|!!   B points at a, which is outside every lane: draw the box outside every lane too
refT|out|!!   T = U(H) points at n, in the lane lib/: draw the box in that lane
refR|out|!!   R points at e', in the lane lib/: draw the box in that lane
refS|out|!!   U(B) points at k, in the lane lib/: draw the box in that lane
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
    -u '//mxCell[@id="refT"]/@value' -v 'THEIRS = BASE = U(HEAD)' \
    -u '//mxCell[@id="refH"]/@value' -v HEAD \
    -u '//mxCell[@id="refB"]/@value' -v BOUNDARY \
    -u '//mxCell[@id="refS"]/@value' -v 'U(BOUNDARY)'
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

@test "drawing: a box U(X) on a commit X's .splice doesn't record" {
  edit_drawing -u '//mxCell[@id="refT"]/@value' -v 'U(a)'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   U(a) points at n, the code says k" ]
}

@test "drawing: a box U(X) for a commit that isn't drawn" {
  edit_drawing -u '//mxCell[@id="refT"]/@value' -v 'U(z)'
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
  git config --file lib/.splice splice.commit "$(git rev-parse HEAD)"
  run check_drawing "$BATS_TEST_DIRNAME/scenarios/01-everyday-sync/01-sync-model/01-after-pull/after-pull.drawio.svg" a=HEAD~4 e=HEAD
  [ "$status" -eq 0 ]
}

@test "drawing: a box without an arrow points nowhere" {
  edit_drawing -d '//mxCell[@source="refT"]'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   T = U(H) has 0 arrows, not one: draw one from the box to its commit" ]
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
  load 'scenarios/03-branches-and-teamwork/03-squash-merged-pull/setup'
  scenario_squash_merged_pull "$BATS_TEST_TMPDIR/squash" "$BATS_TEST_TMPDIR/squash-upstream.git"
  cd "$BATS_TEST_TMPDIR/squash"
  xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' \
    "$BATS_TEST_DIRNAME/scenarios/03-branches-and-teamwork/03-squash-merged-pull/squash-merged-pull.drawio.svg" >"$drawing" 2>/dev/null
  edit_drawing -u '//mxCell[@value="U(H) = U(B) = feature"]/@value' -v 'U(H) = U(B)'
  run check_drawing "$drawing" a=HEAD~2 s=HEAD~1 c=HEAD k=refs/splices/squash-upstream/heads/main f=refs/splices/squash-upstream/heads/feature
  [ "$status" -eq 1 ]
  [ "$output" = "!!   f is on an upstream branch, but not T's: draw a box for the branch, e.g. feature" ]
}

@test "drawing: a commit on another branch of the monorepo is a monorepo commit" {
  load 'scenarios/03-branches-and-teamwork/04-concurrent-pulls/setup'
  scenario_concurrent_pulls "$BATS_TEST_TMPDIR/bob" "$BATS_TEST_TMPDIR/concurrent-upstream.git"
  cd "$BATS_TEST_TMPDIR/bob"
  run check_drawing "$BATS_TEST_DIRNAME/scenarios/03-branches-and-teamwork/04-concurrent-pulls/concurrent-pulls.drawio.svg" \
    a=HEAD~1 p=HEAD q=origin/main k=refs/splices/a/heads/main~2 l=refs/splices/a/heads/main~1 n=refs/splices/a/heads/main
  [ "$status" -eq 0 ]
}

@test "drawing: c' is R's copy of c, though an upstream branch has an older copy, pushed before a 'git rebase'" {
  load 'walkthrough/rebase-feature-branch/setup'
  # Equal dates, as in the docs, leave git log's order to the refs given.
  export GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z
  scenario_feature_branch_behind_default_branch "$BATS_TEST_TMPDIR/rebased" "$BATS_TEST_TMPDIR/rebased-upstream.git"
  git -C "$BATS_TEST_TMPDIR/rebased" rebase -q main
  cd "$BATS_TEST_TMPDIR/rebased"
  run check_drawing "$BATS_TEST_DIRNAME/walkthrough/rebase-feature-branch/rebased-in-the-monorepo.drawio.svg" \
    c=HEAD "b'=refs/splices/a/heads/feature"
  [ "$status" -eq 0 ]
}

@test "drawing: without b'=<rev>, the pushed b' and R's c' after a 'git rebase' look alike, and b' is taken for c'" {
  load 'walkthrough/rebase-feature-branch/setup'
  export GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z
  scenario_feature_branch_behind_default_branch "$BATS_TEST_TMPDIR/rebased" "$BATS_TEST_TMPDIR/rebased-upstream.git"
  local b
  b="$(git -C "$BATS_TEST_TMPDIR/rebased" rev-parse HEAD)"
  git -C "$BATS_TEST_TMPDIR/rebased" rebase -q main
  cd "$BATS_TEST_TMPDIR/rebased"
  run check_drawing "$BATS_TEST_DIRNAME/walkthrough/rebase-feature-branch/rebased-in-the-monorepo.drawio.svg" \
    c=HEAD b="$b"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   b' is solid, but no upstream branch has it: dash it"* ]]
}

@test "drawing: a lane names a splice whose folder Git quotes" {
  load 'scenarios/03-branches-and-teamwork/03-squash-merged-pull/setup'
  scenario_squash_merged_pull "$BATS_TEST_TMPDIR/squash" "$BATS_TEST_TMPDIR/squash-upstream.git"
  cd "$BATS_TEST_TMPDIR/squash"
  mkdir -p vendor/é && cp vendor/a/.splice vendor/é/ && git add vendor/é && git commit -qm "copy the splice"
  xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' \
    "$BATS_TEST_DIRNAME/scenarios/03-branches-and-teamwork/03-squash-merged-pull/squash-merged-pull.drawio.svg" >"$drawing" 2>/dev/null
  edit_drawing -u '//mxCell[@value="vendor/a/"]/@value' -v vendor/é/
  run check_drawing "$drawing"
  [[ "$output" != *"isn't a splice of the monorepo"* ]]
}

@test "drawing: a box next to a monorepo commit names a monorepo branch, though the upstream has one named like it" {
  edit_drawing -u '//mxCell[@id="refH"]/@value' -v 'H = main' -u '//mxCell[@id="refT"]/@value' -v 'T = U(H) = main'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 0 ]
}

@test "drawing: a monorepo branch box pointing at the wrong commit names the right one" {
  edit_drawing -u '//mxCell[@id="refB"]/@value' -v 'B = main'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   main points at a, the code says e" ]
}

@test "drawing: a box names an upstream branch with any characters Git allows" {
  load 'scenarios/03-branches-and-teamwork/03-squash-merged-pull/setup'
  scenario_squash_merged_pull "$BATS_TEST_TMPDIR/squash" "$BATS_TEST_TMPDIR/squash-upstream.git"
  cd "$BATS_TEST_TMPDIR/squash"
  git update-ref refs/splices/squash-upstream/heads/user@feature+1=next refs/splices/squash-upstream/heads/feature
  xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' \
    "$BATS_TEST_DIRNAME/scenarios/03-branches-and-teamwork/03-squash-merged-pull/squash-merged-pull.drawio.svg" >"$drawing" 2>/dev/null
  edit_drawing -u '//mxCell[@value="U(H) = U(B) = feature"]/@value' -v 'U(H) = U(B) = user@feature+1=next'
  run check_drawing "$drawing" a=HEAD~2 s=HEAD~1 c=HEAD k=refs/splices/squash-upstream/heads/main f=refs/splices/squash-upstream/heads/feature
  [ "$status" -eq 0 ]
}

# A plain Git history, without splices, shaped like git subtree's: a
# commit with the library's files merged into the monorepo's history.
plain_history() {
  git init -q -b main "$BATS_TEST_TMPDIR/plain"
  cd "$BATS_TEST_TMPDIR/plain"
  git config user.name Test
  git config user.email test@example.com
  git commit -q --allow-empty -m a
  git switch -q --orphan lib
  git commit -q --allow-empty -m q
  git switch -q main
  git merge -q --allow-unrelated-histories -m s lib
  for c in b c d e; do git commit -q --allow-empty -m "$c"; done
  drawing="$BATS_TEST_TMPDIR/plain.drawio"
  xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' \
    "$BATS_TEST_DIRNAME/comparisons/git-subtree-squashed.drawio.svg" >"$drawing" 2>/dev/null
}

@test "drawing: a monorepo without splices needs no lanes" {
  plain_history
  run check_drawing "$drawing" --alias HEAD=H q=lib
  [ "$status" -eq 0 ]
  [ "$output" = "ok   plain.drawio: 7 commits, 7 arrows, 1 boxes" ]
}

@test "drawing: without splices, a merge's second parent still needs its arrow" {
  plain_history
  edit_drawing -d '//mxCell[@source="q" and @target="s"]'
  run check_drawing "$drawing" --alias HEAD=H q=lib
  [ "$status" -eq 1 ]
  [ "$output" = "!!   no arrow q -> s, though q is a parent of s" ]
}

@test "drawing: without splices, a lane names no splice" {
  plain_history
  sed -i 's#</root>#<mxCell id="lane" parent="1" vertex="1" value="vendor/lib/"><mxGeometry width="900" height="900" as="geometry" /></mxCell></root>#' "$drawing"
  run check_drawing "$drawing" --alias HEAD=H q=lib
  [ "$status" -eq 1 ]
  [ "$output" = "!!   the lane vendor/lib/ isn't a splice of the monorepo" ]
}

@test "drawing: without splices, a commit outside the monorepo's history is named" {
  plain_history
  git commit-tree -m outside "$(git hash-object -t tree /dev/null)" >"$BATS_TEST_TMPDIR/outside"
  run check_drawing "$drawing" --alias HEAD=H q="$(cat "$BATS_TEST_TMPDIR/outside")"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   q isn't a commit of the monorepo, which has no splices" ]
}

# plain_history, with e's message naming a, and a message arrow from e to
# the commit given.
message_arrow() {
  plain_history
  git commit -q --amend --allow-empty -m e -m "Up to $(git rev-parse --short HEAD~5) already split."
  sed -i "s#</root>#<mxCell id=\"m\" parent=\"1\" edge=\"1\" source=\"e\" target=\"$1\" style=\"dashed=1;message=1;\"><mxGeometry relative=\"1\" as=\"geometry\" /></mxCell></root>#" "$drawing"
}

@test "drawing: a message arrow points at a commit the message names by its hash" {
  message_arrow a
  run check_drawing "$drawing" --alias HEAD=H q=lib
  [ "$status" -eq 0 ]
  [ "$output" = "ok   plain.drawio: 7 commits, 8 arrows, 1 boxes" ]
}

@test "drawing: a message arrow at a commit the message doesn't name" {
  message_arrow b
  run check_drawing "$drawing" --alias HEAD=H q=lib
  [ "$status" -eq 1 ]
  [ "$output" = "!!   e's message doesn't name b: point the message arrow at the commit it names" ]
}

@test "drawing: a message arrow joins two commits" {
  message_arrow box0
  run check_drawing "$drawing" --alias HEAD=H q=lib
  [ "$status" -eq 1 ]
  [ "$output" = "!!   a message arrow (m) doesn't join two commits: draw it from a commit to the one its message names" ]
}

# Two circles, x and x', with a box that points at x'.
pushed_copy_drawing() {
  local box="$1" x_style="${2:-ellipse;}" copy_style="${3:-ellipse;}"
  cat >"$drawing" <<XML
<mxfile><diagram id="d"><mxGraphModel><root><mxCell id="0" /><mxCell id="1" parent="0" />
<mxCell id="x" parent="1" vertex="1" style="$x_style" value="x"><mxGeometry x="0" y="0" width="70" height="70" as="geometry" /></mxCell>
<mxCell id="x_" parent="1" vertex="1" style="$copy_style" value="x'"><mxGeometry x="0" y="160" width="70" height="70" as="geometry" /></mxCell>
<mxCell id="box" parent="1" vertex="1" style="rounded=1;" value="$box"><mxGeometry x="120" y="175" width="120" height="40" as="geometry" /></mxCell>
<mxCell id="e0" parent="1" edge="1" source="box" target="x_"><mxGeometry relative="1" as="geometry" /></mxCell>
</root></mxGraphModel></diagram></mxfile>
XML
}

@test "drawing: a rebuilt commit is also found on the upstream branch a push put it on" {
  git switch -q -c feature
  commit_local "$monorepo" lib "x"
  splice push lib >/dev/null 2>&1
  git switch -q main
  pushed_copy_drawing feature
  run check_drawing "$drawing" x=feature
  [ "$status" -eq 0 ]
  [ "$output" = "ok   after-pull.drawio: 2 commits, 1 arrows, 1 boxes" ]
}

@test "drawing: a label also names the commit whose subject starts with it and a colon, and its rebuilt copy" {
  git switch -q -c feature
  commit_local "$monorepo" lib "x: a change"
  splice push lib >/dev/null 2>&1
  pushed_copy_drawing feature
  run check_drawing "$drawing"
  [ "$status" -eq 0 ]
  [ "$output" = "ok   after-pull.drawio: 2 commits, 1 arrows, 1 boxes" ]
}

@test "drawing: a box named as <label>=<rev> points at that revision" {
  git switch -q -c feature
  commit_local "$monorepo" lib "x"
  splice push lib >/dev/null 2>&1
  # On feature, R copies x, as x'.
  pushed_copy_drawing pushed
  run check_drawing "$drawing" x=feature pushed=refs/splices/upstream/heads/feature
  [ "$status" -eq 0 ]
  run check_drawing "$drawing" x=feature pushed=feature
  [ "$status" -eq 1 ]
  [ "$output" = "!!   pushed points at x', the code says x" ]
}
