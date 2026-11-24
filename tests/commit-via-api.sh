#!/usr/bin/env bash
set -euo pipefail

# Exercises commit.sh against a throwaway remote, with a fake `gh` that
# records the GraphQL request and simulates one conflicting attempt.

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

git init --quiet --bare "$sandbox/remote.git"
git clone --quiet "$sandbox/remote.git" "$sandbox/checkout" 2>/dev/null
cd "$sandbox/checkout"
git -c user.email=test@example.com -c user.name=test commit --quiet --allow-empty -m init
printf 'old\n' >keep.txt && printf 'bye\n' >gone.txt
git add . && git -c user.email=test@example.com -c user.name=test commit --quiet -m files
git push --quiet origin HEAD:main

mkdir -p "$sandbox/bin"
cat >"$sandbox/bin/gh" <<FAKE
#!/usr/bin/env bash
count_file="$sandbox/calls"
count=\$(( \$(cat "\$count_file" 2>/dev/null || echo 0) + 1 ))
echo "\$count" >"\$count_file"
while [ \$# -gt 0 ]; do [ "\$1" = "--input" ] && cp "\$2" "$sandbox/request-\$count.json"; shift; done
[ "\$count" -eq 1 ] && { echo "GraphQL: Expected branch to point to ..." >&2; exit 1; }
echo "deadbeef"
FAKE
chmod +x "$sandbox/bin/gh"

export PATH="$sandbox/bin:$PATH" GITHUB_OUTPUT="$sandbox/output"
export INPUT_MESSAGE="test: update" INPUT_REPOSITORY="owner/repo" INPUT_BRANCH="main" INPUT_ATTEMPTS="3"
export INPUT_APPLY='printf "new\n" >keep.txt && mkdir -p "a dir" && printf "x\n" >"a dir/n.txt" && git rm --quiet gone.txt && git add --all'

"$repo_root/commit-via-api/commit.sh"

request="$sandbox/request-2.json"
test "$(cat "$sandbox/calls")" -eq 2
test "$(jq -r '.variables.input.expectedHeadOid' "$request")" = "$(git rev-parse origin/main)"
test "$(jq -r '.variables.input.message.headline' "$request")" = "test: update"
test "$(jq -r '[.variables.input.fileChanges.additions[].path] | sort | join(",")' "$request")" = "a dir/n.txt,keep.txt"
test "$(jq -r '.variables.input.fileChanges.additions[] | select(.path == "keep.txt") | .contents | @base64d' "$request")" = "new"
test "$(jq -r '.variables.input.fileChanges.deletions[].path' "$request")" = "gone.txt"
grep -q '^sha=deadbeef$' "$GITHUB_OUTPUT"

INPUT_APPLY='true' "$repo_root/commit-via-api/commit.sh" | grep -q "Nothing to commit"

echo "commit-via-api tests passed"
