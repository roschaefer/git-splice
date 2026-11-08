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

@test "drawing tree: the first pull after an init is a pull" {
  load '../09-scenarios/02-starting-a-splice/04-init-new-upstream/setup'
  local other="$BATS_TEST_TMPDIR/other" other_upstream="$BATS_TEST_TMPDIR/other.git"
  scenario_init_new_upstream "$other" "$other_upstream"
  cd "$other"
  splice init lib/a "$other_upstream" >/dev/null
  splice push lib/a >/dev/null
  seed_bare_repo "$other_upstream" "u2: upstream" main lib-file.txt
  splice pull lib/a >/dev/null
  cat >"$drawing" <<'XML'
<mxfile><diagram name="t" id="t"><mxGraphModel><root><mxCell id="0"/><mxCell id="1" parent="0"/>
<mxCell id="h" parent="1" vertex="1" value="s" style="ellipse;aspect=fixed;strokeWidth=2;strokeColor=#0070E0;"><mxGeometry x="0" y="0" width="36" height="36" as="geometry"/></mxCell>
<mxCell id="ht" parent="1" vertex="1" value="monorepo" style="text;tree=1;"><mxGeometry x="50" y="0" width="100" height="36" as="geometry"/></mxCell>
<mxCell id="a" parent="1" vertex="1" value="u2" style="ellipse;aspect=fixed;strokeWidth=2;strokeColor=#0070E0;"><mxGeometry x="30" y="60" width="36" height="36" as="geometry"/></mxCell>
<mxCell id="at" parent="1" vertex="1" value="lib/a/" style="text;"><mxGeometry x="200" y="60" width="100" height="36" as="geometry"/></mxCell>
<mxCell id="e" parent="1" edge="1" source="h" target="a" style="endArrow=none;"><mxGeometry relative="1" as="geometry"/></mxCell>
<mxCell id="lg" parent="1" vertex="1" value="" style="rounded=1;fillColor=none;legend=1;"><mxGeometry x="0" y="200" width="200" height="40" as="geometry"/></mxCell>
<mxCell id="lgb" parent="lg" vertex="1" value="" style="ellipse;aspect=fixed;strokeWidth=2;strokeColor=#0070E0;"><mxGeometry x="10" y="8" width="24" height="24" as="geometry"/></mxCell>
</root></mxGraphModel></diagram></mxfile>
XML
  run check_drawing "$drawing" s=HEAD
  [[ "$output" != *"s should be outlined black"* ]]
}

@test "drawing tree: a row that hangs from a splice further out than the one around it" {
  local s b1
  s="$(xmlstarlet sel -t -v '//mxCell[@value="s"]/@id' "$drawing")"
  b1="$(xmlstarlet sel -t -v '//mxCell[@value="b1"]/@id' "$drawing")"
  edit_drawing -u "//mxCell[@edge=\"1\"][@target=\"$b1\"]/@source" -v "$s" \
    -u '//mxCell[@value="b/"]/@value' -v vendor/a/b/
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a/b/ hangs from the monorepo, but the splice around it is vendor/a/: draw its row below that one's"* ]]
}

@test "drawing tree: a commit drawn as merged in with a conflict into a splice the pull doesn't move" {
  commit_local "$monorepo" vendor/a/b/c "c local"
  seed_bare_repo "$BATS_TEST_TMPDIR/upstream-c.git" "c upstream"
  run splice pull vendor/a/b/c
  [ "$status" -ne 0 ]
  local b1 y
  b1="$(xmlstarlet sel -t -v '//mxCell[@value="b1"]/@id' "$drawing")"
  y="$(xmlstarlet sel -t -v "//mxCell[@id=\"$b1\"]/mxGeometry/@y" "$drawing")"
  sed -i "s#</root>#<mxCell id=\"t\" parent=\"1\" vertex=\"1\" value=\"b1\" style=\"ellipse;aspect=fixed;strokeWidth=3;strokeColor=\#D00000;\"><mxGeometry x=\"200\" y=\"$y\" width=\"36\" height=\"36\" as=\"geometry\" /></mxCell><mxCell id=\"tt\" parent=\"1\" edge=\"1\" source=\"t\" target=\"$b1\" style=\"dashed=1;strokeColor=\#D00000;\"><mxGeometry relative=\"1\" as=\"geometry\" /></mxCell></root>#" "$drawing"
  edit_drawing -u '//mxCell[@value="b/"]/mxGeometry/@x' -v 300
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   b1 is drawn as merged into vendor/a/b/ with a conflict, but the pull in progress doesn't move it"* ]]
}

@test "drawing tree: a row hanging from the commit a conflicted pull merges in" {
  commit_local "$monorepo" vendor/a/b "b local"
  seed_bare_repo "$BATS_TEST_TMPDIR/upstream-b.git" "b upstream"
  run splice pull vendor/a/b
  [ "$status" -ne 0 ]
  local b1 c1 y
  b1="$(xmlstarlet sel -t -v '//mxCell[@value="b1"]/@id' "$drawing")"
  c1="$(xmlstarlet sel -t -v '//mxCell[@value="c1"]/@id' "$drawing")"
  y="$(xmlstarlet sel -t -v "//mxCell[@id=\"$b1\"]/mxGeometry/@y" "$drawing")"
  sed -i "s#</root>#<mxCell id=\"t\" parent=\"1\" vertex=\"1\" value=\"b2\" style=\"ellipse;aspect=fixed;strokeWidth=3;strokeColor=\#D00000;\"><mxGeometry x=\"200\" y=\"$y\" width=\"36\" height=\"36\" as=\"geometry\" /></mxCell><mxCell id=\"tt\" parent=\"1\" edge=\"1\" source=\"t\" target=\"$b1\" style=\"dashed=1;strokeColor=\#D00000;\"><mxGeometry relative=\"1\" as=\"geometry\" /></mxCell></root>#" "$drawing"
  edit_drawing -u '//mxCell[@value="b/"]/mxGeometry/@x' -v 300 \
    -u "//mxCell[@edge=\"1\"][@target=\"$c1\"]/@source" -v t
  run check_drawing "$drawing" "${revs[@]}" b2=refs/splices/upstream-b/heads/main
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a/b/c/ hangs from b2, but its parent's head is b1: draw the edge from the head"* ]]
}

@test "drawing tree: a merge that brings a splice's changes in is carried over" {
  git switch -q -c side
  commit_local "$monorepo" vendor/a/b/c "c on a side branch"
  git switch -q main
  git merge -q --no-ff --no-edit side
  sed -i 's#</root>#<mxCell id="lg" parent="1" vertex="1" value="" style="rounded=1;fillColor=none;legend=1;"><mxGeometry x="0" y="400" width="200" height="40" as="geometry" /></mxCell><mxCell id="lgo" parent="lg" vertex="1" value="" style="ellipse;aspect=fixed;strokeWidth=2;strokeColor=\#E07000;"><mxGeometry x="10" y="8" width="24" height="24" as="geometry" /></mxCell></root>#' "$drawing"
  edit_drawing -u '//mxCell[@value="s"]/@style' -v "ellipse;aspect=fixed;strokeWidth=2;strokeColor=#E07000;"
  run check_drawing "$drawing" "${revs[@]}"
  [[ "$output" != *"s should be outlined black"* ]]
}

@test "drawing tree: a label given as an annotated tag names the commit it tags" {
  git tag -a -m "the start" v1
  run check_drawing "$drawing" "${revs[@]/#s=HEAD/s=v1}"
  [ "$status" -eq 0 ]
}
