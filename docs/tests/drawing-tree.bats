# check_drawing on a splice tree, a drawing whose root text is styled
# tree=1, against the three-levels scenario's tree.

setup() {
  load 'helpers/fixtures'
  load '../../check-drawing/check-drawing'
  hermetic_git_config
  load '../09-scenarios/05-nested-splices/01-nested-splices/setup'
  load '../09-scenarios/05-nested-splices/01-nested-splices/02-three-levels/setup'
  PATH="$(dirname "$ENTRYPOINT"):$PATH"
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  scenario_three_levels "$monorepo" "$upstream"
  cd "$monorepo"
  drawing="$BATS_TEST_TMPDIR/tree.drawio"
  xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' \
    "$BATS_TEST_DIRNAME/../09-scenarios/05-nested-splices/01-nested-splices/02-three-levels/tree.drawio.svg" >"$drawing" 2>/dev/null
  revs=(s=HEAD a1=refs/splices/upstream/heads/main b1=refs/splices/upstream-b/heads/main c1=refs/splices/upstream-c/heads/main)
}

edit_drawing() {
  xmlstarlet ed -L "$@" "$drawing"
}

@test "drawing tree: the committed one matches its scenario" {
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 0 ]
  [ "$output" = "ok   tree.drawio: a tree of 4 rows" ]
}

@test "drawing tree: a synced commit the parent doesn't record" {
  run check_drawing "$drawing" "${revs[@]/#c1=*/c1=HEAD}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   c1 is vendor/a/b/c/'s synced commit, but the code says "* ]]
}

@test "drawing tree: a row for a folder that isn't a splice" {
  edit_drawing -u '//mxCell[@value="c/"]/@value' -v x/
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a/b/x/ isn't a splice of the monorepo"* ]]
  [[ "$output" == *"!!   vendor/a/b/c is a splice of the monorepo, but has no row: draw one, so the tree shows every splice"* ]]
}

@test "drawing tree: a splice with commits of its own, without R" {
  commit_local "$monorepo" vendor/a/b/c "c local"
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a/b/c/ has commits of its own: draw R, c local ("* ]]
}

@test "drawing tree: a colored commit without a legend that explains it" {
  edit_drawing -u '//mxCell[@value="b1"]/@style' -v "ellipse;aspect=fixed;strokeWidth=2;strokeColor=#0070E0;"
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   b1 should be outlined black"* ]]
}

@test "drawing tree: a commit that changes only what a .splice says besides its commit isn't a pull" {
  git config --file vendor/a/.splice upstream.origin.pushurl https://git.example.com/a-push.git
  git commit -q -am "a's push URL"
  sed -i 's#</root>#<mxCell id="lg" parent="1" vertex="1" value="" style="rounded=1;fillColor=none;legend=1;"><mxGeometry x="0" y="400" width="200" height="40" as="geometry" /></mxCell><mxCell id="lgb" parent="lg" vertex="1" value="" style="ellipse;aspect=fixed;strokeWidth=2;strokeColor=\#0070E0;"><mxGeometry x="10" y="8" width="24" height="24" as="geometry" /></mxCell></root>#' "$drawing"
  edit_drawing -u '//mxCell[@value="s"]/@style' -v "ellipse;aspect=fixed;strokeWidth=2;strokeColor=#0070E0;"
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   s should be outlined black"* ]]
}

@test "drawing tree: a circle in a row that's neither its synced commit, R nor what a pull merges in" {
  sed -i 's#</root>#<mxCell id="x" parent="1" vertex="1" value="x" style="ellipse;aspect=fixed;strokeWidth=2;"><mxGeometry x="300" y="0" width="36" height="36" as="geometry" /></mxCell></root>#' "$drawing"
  edit_drawing -u '//mxCell[@value="monorepo"]/mxGeometry/@x' -v 400
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   x is in the row of the monorepo, but is neither its head"* ]]
}

@test "drawing tree: a label with a ' names a copy, not the commit itself" {
  edit_drawing -u '//mxCell[@value="c1"]/@value' -v "c seed'"
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   c seed' is vendor/a/b/c/'s synced commit, but the code says"* ]]
}
