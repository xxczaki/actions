#!/usr/bin/env bash
set -euo pipefail

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

create_commit() {
	local head_oid
	head_oid="$(git rev-parse HEAD)"

	git diff --cached --no-renames --name-only --diff-filter=d -z |
		while IFS= read -r -d '' path; do
			jq --null-input --arg path "$path" --rawfile contents <(base64 <"$path" | tr -d '\n') \
				'{path: $path, contents: $contents}'
		done | jq --slurp . >"$work_dir/additions.json" || return 1

	git diff --cached --no-renames --name-only --diff-filter=D -z |
		while IFS= read -r -d '' path; do
			jq --null-input --arg path "$path" '{path: $path}'
		done | jq --slurp . >"$work_dir/deletions.json" || return 1

	jq --null-input \
		--arg repository "$INPUT_REPOSITORY" \
		--arg branch "$INPUT_BRANCH" \
		--arg head_oid "$head_oid" \
		--arg headline "$INPUT_MESSAGE" \
		--slurpfile additions "$work_dir/additions.json" \
		--slurpfile deletions "$work_dir/deletions.json" \
		'{
			query: "mutation($input: CreateCommitOnBranchInput!) { createCommitOnBranch(input: $input) { commit { oid url } } }",
			variables: {
				input: {
					branch: {repositoryNameWithOwner: $repository, branchName: $branch},
					expectedHeadOid: $head_oid,
					message: {headline: $headline},
					fileChanges: {additions: $additions[0], deletions: $deletions[0]}
				}
			}
		}' >"$work_dir/request.json" || return 1

	# `if create_commit` disables errexit inside this function, so fail explicitly
	gh api graphql --input "$work_dir/request.json" --jq '.data.createCommitOnBranch.commit.oid' >"$work_dir/oid" || return 1
	[ -s "$work_dir/oid" ] || return 1
	echo "Created $(cat "$work_dir/oid")"
	echo "sha=$(cat "$work_dir/oid")" >>"$GITHUB_OUTPUT"
	if [ "${INPUT_SYNC_CHECKOUT:-false}" = "true" ]; then
		git fetch --quiet origin "$INPUT_BRANCH"
		git reset --quiet --hard "origin/$INPUT_BRANCH"
	fi
}

nothing_staged() {
	if git diff --cached --quiet; then
		echo "Nothing to commit"
		echo "sha=" >>"$GITHUB_OUTPUT"
		return 0
	fi
	return 1
}

if [ -z "$INPUT_APPLY" ]; then
	nothing_staged && exit 0
	create_commit
	exit 0
fi

for attempt in $(seq 1 "$INPUT_ATTEMPTS"); do
	git fetch --quiet origin "$INPUT_BRANCH"
	git reset --quiet --hard "origin/$INPUT_BRANCH"
	bash -euo pipefail -c "$INPUT_APPLY"
	nothing_staged && exit 0
	if create_commit; then
		exit 0
	fi
	echo "Attempt ${attempt} failed, retrying on top of the latest ${INPUT_BRANCH}"
	sleep $((attempt * 2))
done

echo "::error::Could not create the commit after ${INPUT_ATTEMPTS} attempts"
exit 1
