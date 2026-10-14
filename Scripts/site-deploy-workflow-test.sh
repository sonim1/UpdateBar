#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/site-deploy.yml"
CHECK="$ROOT/Scripts/site-postdeploy-check.sh"

[[ -f "$WORKFLOW" ]] || { echo "site deploy workflow is missing" >&2; exit 1; }
[[ -x "$CHECK" ]] || { echo "site post-deploy check is missing or not executable" >&2; exit 1; }

ruby -rpsych - "$WORKFLOW" <<'RUBY'
workflow = Psych.safe_load(File.binread(ARGV.fetch(0)), permitted_classes: [], permitted_symbols: [], aliases: false)
raise "wrong workflow name" unless workflow["name"] == "Deploy landing site"
raise "site deploy must be push-only" unless workflow["on"] == {
  "push" => { "branches" => ["main"], "paths" => ["docs/**"] },
}
raise "site deploy permissions must be read-only" unless workflow["permissions"] == { "contents" => "read" }
raise "site deploy concurrency must serialize production" unless workflow["concurrency"] == {
  "group" => "landing-production",
  "cancel-in-progress" => false,
}

jobs = workflow.fetch("jobs")
raise "site deploy must contain one job" unless jobs.keys == ["deploy"]
job = jobs.fetch("deploy")
raise "site deploy must hard-gate main pushes" unless job["if"] == "${{ github.event_name == 'push' && github.ref == 'refs/heads/main' }}"
raise "site deploy must use the pinned runner" unless job["runs-on"] == "ubuntu-24.04"
raise "site deploy job permissions must be read-only" unless job["permissions"] == { "contents" => "read" }

steps = job.fetch("steps")
raise "site deploy step order changed" unless steps.map { |step| step["name"] } == [
  "Checkout main source",
  "Set up Node.js",
  "Validate landing contract",
  "Resolve deployment source",
  "Deploy to Cloudflare Pages",
  "Verify production",
]
steps.each do |step|
  next unless step["uses"]
  raise "external actions must use full SHAs" unless step.fetch("uses").match?(/\A[^@]+@[0-9a-f]{40}\z/)
end

checkout, node, contract, marker, deploy, verify = steps
raise "checkout must fetch current main without persisting credentials" unless checkout == {
  "name" => "Checkout main source",
  "uses" => "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1",
  "with" => { "ref" => "main", "persist-credentials" => false },
}
raise "Pages deploy must use an explicit Node 24 toolchain" unless node == {
  "name" => "Set up Node.js",
  "uses" => "actions/setup-node@820762786026740c76f36085b0efc47a31fe5020",
  "with" => { "node-version" => 24 },
}
raise "landing contract precheck changed" unless contract == {
  "name" => "Validate landing contract",
  "run" => "bash Scripts/landing-contract-test.sh",
}
raise "source marker must bind the deployed commit" unless marker == {
  "name" => "Resolve deployment source",
  "id" => "source",
  "shell" => "bash",
  "run" => <<~SHELL,
    set -euo pipefail
    source_sha="$(git rev-parse HEAD)"
    if [[ ! "$source_sha" =~ ^[0-9a-f]{40}$ ]]; then
      echo "checked-out source SHA is not canonical" >&2
      exit 64
    fi
    printf '%s\\n' "$source_sha" > docs/deployment-source.txt
    printf 'sha=%s\\n' "$source_sha" >> "$GITHUB_OUTPUT"
  SHELL
}
raise "Pages deployment contract changed" unless deploy == {
  "name" => "Deploy to Cloudflare Pages",
  "uses" => "cloudflare/wrangler-action@953926a2e2182532811c01a25e53647d93bf07c0",
  "with" => {
    "apiToken" => "${{ secrets.CLOUDFLARE_API_TOKEN }}",
    "accountId" => "${{ vars.CLOUDFLARE_ACCOUNT_ID }}",
    "wranglerVersion" => "4.151.0",
    "command" => "pages deploy docs --project-name=updatebar-landing --branch=main --commit-hash=${{ steps.source.outputs.sha }} --commit-dirty=true",
  },
}
raise "production verification changed" unless verify == {
  "name" => "Verify production",
  "env" => { "SOURCE_SHA" => "${{ steps.source.outputs.sha }}" },
  "run" => "bash Scripts/site-postdeploy-check.sh https://updatebar.royjen.com \"$SOURCE_SHA\"",
}

serialized = workflow.to_s
secrets = serialized.scan(/secrets[.][A-Za-z0-9_]+/).sort
raise "site deploy may receive only the Cloudflare API token secret" unless secrets == %w[secrets.CLOUDFLARE_API_TOKEN]
variables = serialized.scan(/vars[.][A-Za-z0-9_]+/).sort
raise "site deploy must receive the account ID only as configuration" unless variables == %w[vars.CLOUDFLARE_ACCOUNT_ID]
raise "site deploy must not receive a GitHub write token" if serialized.include?("GITHUB_TOKEN") || serialized.include?("gitHubToken")
raise "site deploy must not bind deployment metadata to the stale event SHA" if serialized.include?("${{ github.sha }}")
RUBY

echo 'site deploy workflow contract passed'
