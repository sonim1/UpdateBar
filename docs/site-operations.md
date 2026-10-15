# UpdateBar website operations

Production: `https://updatebar.royjen.com/`. Cloudflare Pages project:
`updatebar-landing`, production branch `main`, static output `docs/`.

The landing site uses Wrangler direct uploads. App/CLI releases, signing,
Homebrew and Sparkle publishing are separate from the website.

## Production deployment

`.github/workflows/site-deploy.yml` publishes after a push to `main` changes a
file under `docs/`. When each serialized job starts, it checks out the current
reviewed `main`, selects Node.js 24, and runs `Scripts/landing-contract-test.sh`.
It writes the checked-out commit to `deployment-source.txt`, attaches that same
commit to the Pages deployment, then checks the public home page, source marker
and a route that must return a real HTTP 404. Reading `main` at execution time
prevents an older queued event from deploying an older commit after a newer
deployment. Production deployments are never triggered by a pull request.

The repository must have this GitHub Actions variable and secret before the
workflow can deploy:

- Repository variable `CLOUDFLARE_ACCOUNT_ID`: the non-sensitive account ID
  that owns `updatebar-landing`.
- Repository secret `CLOUDFLARE_API_TOKEN`: an account token limited to that
  account with
  `Cloudflare Pages: Edit` permission.

An administrator must add or rotate the secret and maintain the variable in
GitHub. Do not put token values in repository files, shell history, workflow
output or Dependabot secrets. The workflow does not receive a GitHub write token
and does not run for bot or fork code.

For a manual preview, first run `bash Scripts/landing-contract-test.sh`, then:

```bash
npx wrangler pages deploy docs --project-name updatebar-landing --branch site-review
```

Production publication uses `--branch main`. The checked-in workflow is the
normal production path. After an incident, use the Cloudflare Pages deployment
history to identify and roll back to the last known-good production deployment,
then repair `main`; do not upload an unreviewed local directory as a lasting
fix. Refresh the stylesheet hash in HTML only when changing CSS, following
`docs/DESIGN.md`.

Run the production HTTP contract manually with the commit SHA shown by Pages:

```bash
bash Scripts/site-postdeploy-check.sh https://updatebar.royjen.com 0123456789abcdef0123456789abcdef01234567
```

Cloudflare Pages Web Analytics is configured through Metrics and injected at
deployment. Keep one beacon per page; do not add another manual snippet. The
CSP allows the Cloudflare script and measurement endpoint. Native app and CLI
telemetry remains disabled. See the shared
[website privacy notice](https://royjen.com/privacy/).

The [shared Royjen site runbook](https://github.com/sonim1/royjen/blob/main/docs/site-operations.md)
defines search ownership, analytics dimensions, weekly reporting and deployment
checks for all three sites. Filter analytics by the production Host and exclude
bots. Visits and referrals are not downloads or successful tool updates.
Cloudflare Web Analytics does not report UTM campaigns or custom events; see
the [Cloudflare Web Analytics FAQ](https://developers.cloudflare.com/web-analytics/faq/).

## Download counts

Generate a point-in-time Markdown report for public GitHub release assets with:

```bash
bash Scripts/release-download-counts.sh > release-download-counts.md
```

The report sums GitHub's `download_count` for uploaded release assets. A
download is a transfer count, not a unique user, installation or active device.
It excludes source archives and downloads served by the Sparkle/R2 update host,
so it is incomplete by design. Keep Cloudflare Web Analytics as the website
traffic source and do not add native app or CLI telemetry to fill this gap.
