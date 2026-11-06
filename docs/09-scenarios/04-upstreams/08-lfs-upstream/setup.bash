# See README.md in this directory. Needs Git LFS's filter in the global
# config, as `git lfs install` writes it, and the monorepo's remote
# reached as https://git.example.com/monorepo.git, as README.md sets up.

# Commits file $2 with content $3 and message $4 to branch main of bare
# repository $1, with *.bin files stored in Git LFS.
commit_lfs_file() {
  local repo="$1" file="$2" content="$3" message="$4" tmp
  tmp="$(mktemp -d)"
  # A file:// URL: Git LFS transfers the objects of a local repository
  # only for those.
  git clone -q "file://$repo" "$tmp" 2>/dev/null
  (
    cd "$tmp"
    git lfs track '*.bin' >/dev/null
    echo "$content" >"$file"
    git add .gitattributes "$file"
    git -c user.name=Test -c user.email=test@example.com commit -q -m "$message"
    git push -q origin HEAD:main
  )
  rm -rf "$tmp"
}

scenario_lfs_upstream() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  commit_lfs_file "$upstream" model.bin "weights, version 1" "add the model"
  make_bare_repo "$monorepo.git"
  init_monorepo "$monorepo"
  (
    cd "$monorepo"
    git remote add origin https://git.example.com/monorepo.git
    git push -q origin main
  )
}
