# See README.md in this directory. Needs git-crypt.

# Writes a git-crypt key file to $1 with fixed keys, so the encrypted
# blobs, and the hashes of the commits holding them, are the same on
# every run. git-crypt's format 2: a header without fields, then one key,
# version 0, with an AES key of 32 bytes 0x11 and an HMAC key of 64 bytes
# 0x22.
write_git_crypt_key() {
  {
    printf '\0GITCRYPTKEY\0\0\0\2\0\0\0\0'
    printf '\0\0\0\1\0\0\0\4\0\0\0\0'
    printf '\0\0\0\3\0\0\0\40'
    head -c 32 /dev/zero | tr '\0' '\021'
    printf '\0\0\0\5\0\0\0\100'
    head -c 64 /dev/zero | tr '\0' '\042'
    printf '\0\0\0\0'
  } >"$1"
}

scenario_encrypted_upstream() {
  local monorepo="$1" upstream="$2" key tmp
  key="$(dirname "$monorepo")/git-crypt.key"
  write_git_crypt_key "$key"
  make_bare_repo "$upstream"
  tmp="$(mktemp -d)"
  git clone -q "$upstream" "$tmp" 2>/dev/null
  (
    cd "$tmp" || exit
    git-crypt unlock "$key"
    printf '%s\n' '** filter=git-crypt diff=git-crypt' '.gitattributes !filter !diff' >.gitattributes
    echo "secret, version 1" >secret.txt
    git add .gitattributes secret.txt
    git -c user.name=Test -c user.email=test@example.com commit -q -m "a: add secret.txt, encrypted"
    git push -q origin HEAD:main
  )
  rm -rf "$tmp"
  init_monorepo "$monorepo"
  (cd "$monorepo" && git-crypt unlock "$key")
}
