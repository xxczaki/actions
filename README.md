# xxczaki/actions

Shared GitHub Actions for my repositories.

## `commit-via-api`

Creates a commit through the GraphQL `createCommitOnBranch` mutation, so GitHub signs it and it shows as **Verified**, without a GPG key in CI. Works with `GITHUB_TOKEN` or a GitHub App installation token.

With `apply`, every attempt resets to the latest remote branch, runs the script (which must stage its changes) and commits, retrying when another push got there first.

```yaml
- uses: xxczaki/actions/commit-via-api@<full commit sha> # v1.0.0
  with:
    token: ${{ steps.app-token.outputs.token }}
    repository: xxczaki/homelab
    branch: main
    working-directory: homelab
    message: "chore(app): deploy ${{ github.sha }}"
    apply: |
      yq -i '.spec.source.targetRevision = strenv(GITHUB_SHA)' apps/app/application.yaml
      git add apps/app/application.yaml
```

Without `apply`, the changes already staged in `working-directory` are committed once. `sync-checkout: true` resets the checkout to the new commit afterwards.

| Input | Default | |
|---|---|---|
| `token` | – | `contents: write` on the target repository |
| `message` | – | Commit headline |
| `repository` | current repository | `owner/name` |
| `branch` | current branch | |
| `working-directory` | `.` | Checkout of the target repository |
| `apply` | – | Script that makes and stages the change |
| `attempts` | `5` | Attempts when `apply` is set |
| `sync-checkout` | `false` | Reset the checkout to the new commit |

Output: `sha` of the created commit, empty when there was nothing to commit.

Pin it by full commit SHA. File modes (e.g. the executable bit) are not preserved by the API.
