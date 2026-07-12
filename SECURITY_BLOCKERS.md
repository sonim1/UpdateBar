# Security Blockers

## GitHub branch protection for CODEOWNERS

- **Blocked item:** Enforce owner review for `.github/workflows/*`, `Scripts/*`, and `Packaging/homebrew/**` changes.
- **Why I cannot complete it:** The repo-local `.github/CODEOWNERS` file is present, but GitHub branch protection and required review settings live in repository settings outside this checkout.
- **User action:** Enable branch protection or rulesets for protected branches and require CODEOWNERS review before merging matching changes.
- **Needed material or decision:** Confirm the protected branch pattern, required reviewer policy, and whether `@sonim1` is the desired owner for release automation and packaging paths.
- **Next step after resolution:** Re-run the security/CI review and confirm workflow/package changes require owner approval in GitHub.
- **Why no workaround:** A local CODEOWNERS file without GitHub enforcement improves visibility but cannot guarantee review by itself.
