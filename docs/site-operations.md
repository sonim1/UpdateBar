# UpdateBar website operations

Production: `https://updatebar.royjen.com/`. Cloudflare Pages project:
`updatebar-landing`, production branch `main`, static output `docs/`.

The landing site uses Wrangler direct uploads. There is no checked-in landing
deployment workflow. App/CLI releases, signing, Homebrew and Sparkle publishing
are separate from the website.

Run `bash Scripts/landing-contract-test.sh` before publication. Preview with:

```bash
npx wrangler pages deploy docs --project-name updatebar-landing --branch site-review
```

Production publication uses `--branch main`. Verify `/`, `/macos/`,
`/cli-agents/`, robots.txt, the sitemap, a true 404, installation links, the
copy-prompt button and mobile layout. Refresh the stylesheet hash in HTML only
when changing CSS, following `docs/DESIGN.md`.

Cloudflare Pages Web Analytics is configured through Metrics and injected at
deployment. Keep one beacon per page; do not add another manual snippet. The
CSP allows the Cloudflare script and measurement endpoint. Native app and CLI
telemetry remains disabled. See the shared
[website privacy notice](https://royjen.com/privacy/).

The [shared Royjen site runbook](https://github.com/sonim1/royjen/blob/main/docs/site-operations.md)
defines search ownership, analytics dimensions, weekly reporting and deployment
checks for all three sites. Filter analytics by the production Host and exclude
bots. Visits and referrals are not downloads or successful tool updates.
Cloudflare Web Analytics does not report UTM campaigns or custom events.
