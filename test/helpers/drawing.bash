# shellcheck shell=bash
# Checks a draw.io drawing of a splice's commit graphs against the
# repositories a scenario built: what the drawing shows, not where. Run in
# the monorepo; see test/scenarios/sync-model/README.md.
#
# The drawing's vocabulary:
#
#   - A circle (ellipse) is a commit. Its label is the commit's subject,
#     looked up on the monorepo's first-parent history, then upstream. A
#     label with a trailing + is the rebuild's copy of the commit without
#     it: the same message, author and dates, in R's history.
#   - An arrow between two commits points from a parent to its child.
#   - A box points at the commit its label names: H, B, U, S, T or R
#     (test/concepts/sync-model/README.md), or U(x), the commit drawn
#     commit x's .splice records. Several names are joined by " = ", e.g.
#     "S = U(a)": each must name that commit.
#   - A frame labelled "x:<path>/.splice", Git's name for that file in
#     commit x, holds commit x, and usually the box U(x).
#   - Dashed commits and arrows into them exist only as the rebuild: in
#     R's history, but not in T's.
#
# Labels that aren't subjects, like the commit add_splice makes, are given
# as label=rev arguments, revs of the monorepo.

# check_drawing <drawing> [<label>=<rev>...]
# Prints "ok" and what it checked, or each difference, and fails.
check_drawing() {
  local drawing="$1" xml path
  shift
  local -A rev_of=() commit_of=() label_of=() kind=() value=() style=() source=() target=() parent=()
  local -A gx=() gy=() gw=() gh=() truth=()
  local -a errors=() commits=() edges=() boxes=() frames=()
  local -A id_of_label=()
  local arg id k v cells term named
  local name='([HBUSTR]|U\([^()]+\))'
  local box_label="^$name( = $name)*\$"

  for arg in "$@"; do
    rev_of[${arg%%=*}]="${arg#*=}"
  done

  if [[ "$drawing" == *.svg ]]; then
    xml="$(xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' "$drawing" 2>/dev/null)"
  else
    xml="$(cat "$drawing")"
  fi
  if [[ "$(xmlstarlet sel -T -t -v 'count(//mxGraphModel)' <<<"$xml" 2>/dev/null)" != 1 ]]; then
    printf '!!   %s: no diagram inside, or a compressed one: save it with File > Properties > Compressed off\n' "${drawing##*/}"
    return 1
  fi

  # One line per cell, fields separated by \x1f: read collapses repeated
  # tabs, and so would shift the fields after an empty one. Labels are
  # plain text: no html=1.
  cells="$(xmlstarlet sel -T -t -m '//mxCell[@id!="0" and @id!="1"]' \
    -v '@id' -o $'\x1f' -v 'concat("v",@vertex,"e",@edge)' -o $'\x1f' -v '@value' -o $'\x1f' -v '@style' -o $'\x1f' \
    -v '@source' -o $'\x1f' -v '@target' -o $'\x1f' -v '@parent' -o $'\x1f' \
    -v 'mxGeometry/@x' -o $'\x1f' -v 'mxGeometry/@y' -o $'\x1f' -v 'mxGeometry/@width' -o $'\x1f' -v 'mxGeometry/@height' -n <<<"$xml")"
  local c_id c_kind c_value c_style c_source c_target c_parent c_x c_y c_w c_h
  while IFS=$'\x1f' read -r c_id c_kind c_value c_style c_source c_target c_parent c_x c_y c_w c_h; do
    [[ -n "$c_id" ]] || continue
    value[$c_id]="$c_value" style[$c_id]="$c_style" source[$c_id]="$c_source" target[$c_id]="$c_target"
    parent[$c_id]="$c_parent" gx[$c_id]="${c_x:-0}" gy[$c_id]="${c_y:-0}" gw[$c_id]="${c_w:-0}" gh[$c_id]="${c_h:-0}"
    if [[ "$c_kind" == *e1 ]]; then
      kind[$c_id]=edge
      edges+=("$c_id")
    elif [[ "$c_value" =~ ^[^\ :]+:.*/\.splice$ ]]; then
      kind[$c_id]=frame
      frames+=("$c_id")
    elif [[ "$c_value" =~ $box_label ]]; then
      kind[$c_id]=box
      boxes+=("$c_id")
    elif [[ "$c_style" == ellipse* || "$c_style" == *";ellipse"* ]]; then
      kind[$c_id]=commit
      commits+=("$c_id")
    fi
  done <<<"$cells"

  if [[ ${#commits[@]} -eq 0 ]]; then
    printf '!!   %s: no commits drawn\n' "${drawing##*/}"
    return 1
  fi

  # The splice, and the commits its letters name.
  path="$(git ls-files -- '*/.splice')"
  path="${path%/.splice}"
  [[ -n "$path" && "$path" != *$'\n'* ]] || {
    printf '!!   the monorepo must have exactly one splice\n'
    return 1
  }
  truth[H]="$(git rev-parse HEAD)"
  truth[B]="$(git splice boundary "$path")"
  truth[U]="$(git config --file "$path/.splice" splice.commit)"
  truth[S]="$(git config --blob "${truth[B]}:$path/.splice" splice.commit)"
  truth[T]="$(git rev-parse --verify --quiet "refs/splices/$(git splice key "$path")/$(git branch --show-current)")"
  truth[R]="$(git splice rebuild "$path")"

  # Commits, by label.
  local label base subject hash upstream_tips=()
  for k in T R U S; do
    [[ -n "${truth[$k]}" ]] && upstream_tips+=("${truth[$k]}")
  done
  for id in "${commits[@]}"; do
    label="${value[$id]}"
    base="${label%+}"
    hash=""
    if [[ -n "${rev_of[$base]:-}" ]]; then
      hash="$(git rev-parse --verify --quiet "${rev_of[$base]}^{commit}")"
    else
      hash="$(git log --first-parent --format='%H%x09%s' HEAD | awk -F'\t' -v s="$base" '$2 == s { print $1; exit }')"
      [[ -n "$hash" || "$label" == *+ ]] ||
        hash="$(git log --format='%H%x09%s' "${upstream_tips[@]}" | awk -F'\t' -v s="$base" '$2 == s { print $1; exit }')"
    fi
    if [[ -n "$hash" && "$label" == *+ ]]; then
      subject="$(git log -1 --format='%B%x1f%an%x1f%aD' "$hash")"
      hash="$(git log --format='%H' "${truth[R]}" | while read -r k; do
        [[ "$k" != "$hash" && "$(git log -1 --format='%B%x1f%an%x1f%aD' "$k")" == "$subject" ]] && { echo "$k"; break; }
      done)"
    fi
    if [[ -z "$hash" ]]; then
      errors+=("$label: no such commit")
      continue
    fi
    commit_of[$id]="$hash"
    label_of[$hash]="$label"
    id_of_label[$label]="$id"
  done

  # A commit exists only as the rebuild if R has it and T doesn't.
  only_rebuilt() {
    git merge-base --is-ancestor "$1" "${truth[R]}" &&
      ! { [[ -n "${truth[T]}" ]] && git merge-base --is-ancestor "$1" "${truth[T]}"; } &&
      ! git merge-base --is-ancestor "$1" HEAD 2>/dev/null
  }
  dashed() { [[ ";${style[$1]};" == *";dashed=1;"* ]]; }

  for id in "${commits[@]}"; do
    [[ -n "${commit_of[$id]:-}" ]] || continue
    if only_rebuilt "${commit_of[$id]}"; then
      dashed "$id" || errors+=("${value[$id]} is solid, but only the rebuild has it: dash it")
    else
      dashed "$id" && errors+=("${value[$id]} is dashed, but it exists outside the rebuild: draw it solid")
    fi
  done

  # Arrows: between commits, parent to child; from a box, to its commit.
  local s t drawn_edges=" "
  for id in "${edges[@]}"; do
    s="${source[$id]}" t="${target[$id]}"
    if [[ -z "$s" || -z "$t" ]]; then
      errors+=("an arrow (${id}) isn't attached at both ends: drag its ends onto shapes")
      continue
    fi
    if [[ "${kind[$s]:-}" == box ]]; then
      if [[ "${kind[$t]:-}" != commit ]]; then
        errors+=("${value[$s]} points at something other than a commit")
        continue
      fi
      while IFS= read -r term; do
        named=""
        if [[ "$term" == U\(*\) ]]; then
          k="${term#U(}" k="${k%)}"
          if [[ -z "${id_of_label[$k]:-}" || -z "${commit_of[${id_of_label[$k]}]:-}" ]]; then
            errors+=("$term points at ${value[$t]}, but no commit $k is drawn")
            continue
          fi
          named="$(git config --blob "${commit_of[${id_of_label[$k]}]}:$path/.splice" splice.commit 2>/dev/null)"
        else
          named="${truth[$term]}"
        fi
        if [[ -z "$named" ]]; then
          errors+=("$term points at ${value[$t]}, but there's no $term")
        elif [[ "${commit_of[$t]:-}" != "$named" ]]; then
          label="${label_of[$named]:-}"
          [[ -n "$label" ]] || label="${named:0:7}, which isn't drawn"
          errors+=("$term points at ${value[$t]}, the code says $label")
        fi
      done < <(sed 's/ = /\n/g' <<<"${value[$s]}")
      continue
    fi
    [[ "${kind[$s]:-}" == commit && "${kind[$t]:-}" == commit ]] || continue
    [[ -n "${commit_of[$s]:-}" && -n "${commit_of[$t]:-}" ]] || continue
    drawn_edges+="$s>$t "
    if ! git rev-parse "${commit_of[$t]}^@" | grep -qx "${commit_of[$s]}"; then
      errors+=("${value[$s]} -> ${value[$t]}: ${value[$s]} isn't a parent of ${value[$t]}")
    elif only_rebuilt "${commit_of[$t]}"; then
      dashed "$id" || errors+=("${value[$s]} -> ${value[$t]} is solid, but ${value[$t]} exists only as the rebuild: dash it")
    else
      dashed "$id" && errors+=("${value[$s]} -> ${value[$t]} is dashed, but ${value[$t]} exists outside the rebuild: draw it solid")
    fi
  done
  # Every parent link between two drawn commits is drawn.
  local p
  for t in "${commits[@]}"; do
    [[ -n "${commit_of[$t]:-}" ]] || continue
    for p in $(git rev-parse "${commit_of[$t]}^@"); do
      for s in "${commits[@]}"; do
        [[ "${commit_of[$s]:-}" == "$p" && "$drawn_edges" != *" $s>$t "* ]] &&
          errors+=("no arrow ${value[$s]} -> ${value[$t]}, though ${value[$s]} is a parent of ${value[$t]}")
      done
    done
  done

  # Frames: "x:<path>/.splice" holds commit x.
  absolute() {
    local cell="$1" x=0 y=0
    while [[ -n "$cell" && "$cell" != 1 && -n "${gx[$cell]+set}" ]]; do
      x=$(awk -v a="$x" -v b="${gx[$cell]}" 'BEGIN { print a + b }')
      y=$(awk -v a="$y" -v b="${gy[$cell]}" 'BEGIN { print a + b }')
      cell="${parent[$cell]}"
    done
    printf '%s %s\n' "$x" "$y"
  }
  local f fx fy cx cy inside
  for f in "${frames[@]}"; do
    k="${value[$f]%%:*}"
    read -r fx fy < <(absolute "$f")
    inside=()
    for id in "${commits[@]}"; do
      read -r cx cy < <(absolute "$id")
      awk -v cx="$cx" -v cy="$cy" -v w="${gw[$id]}" -v h="${gh[$id]}" -v fx="$fx" -v fy="$fy" -v fw="${gw[$f]}" -v fh="${gh[$f]}" \
        'BEGIN { x = cx + w / 2; y = cy + h / 2; exit !(x >= fx && x <= fx + fw && y >= fy && y <= fy + fh) }' &&
        inside+=("$id")
    done
    if [[ ${#inside[@]} -ne 1 ]]; then
      errors+=("the frame \"${value[$f]}\" holds ${#inside[@]} commits, not one")
      continue
    fi
    id="${inside[0]}"
    [[ "${value[$id]}" == "$k" ]] ||
      errors+=("the frame \"${value[$f]}\" holds ${value[$id]}, not $k")
  done

  if [[ ${#errors[@]} -gt 0 ]]; then
    printf '!!   %s\n' "${errors[@]}"
    return 1
  fi
  printf 'ok   %s: %d commits, %d arrows, %d boxes, %d frames\n' \
    "${drawing##*/}" "${#commits[@]}" "${#edges[@]}" "${#boxes[@]}" "${#frames[@]}"
}
