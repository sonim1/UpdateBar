# Manifest

Default path:

```text
~/.updatebar/manifest.json
```

Shape:

```json
{
  "schema_version": 1,
  "items": [
    {
      "id": "fixture-tool",
      "name": "Fixture Tool",
      "category": "cli",
      "path": null,
      "source": { "kind": "custom", "ref": "fixture-tool", "branch": null },
      "version_scheme": "semver",
      "check": { "cmd": "printf 'fixture-tool 1.0.0'" },
      "latest": { "strategy": "cmd", "cmd": "printf 'fixture-tool 1.1.0'", "pattern": null },
      "version_parse": { "regex": "([0-9]+\\.[0-9]+\\.[0-9]+)" },
      "update": { "cmd": "printf updated", "requires_write": true, "cwd": null },
      "pin": null,
      "enabled": true,
      "trust": { "level": "untrusted", "approved_commands": {} }
    }
  ],
  "provenance": {
    "created_by": "updatebar",
    "created_at": "2026-06-09T00:00:00Z",
    "updated_at": "2026-06-09T00:00:00Z"
  }
}
```

Rules:

- `schema_version` must be `1`.
- `provenance.created_by`, `provenance.created_at`, and `provenance.updated_at` are required; timestamps use ISO-8601 date-time strings.
- `id` must match `^[a-z0-9][a-z0-9._-]*$`.
- `source.kind`: `git`, `npm`, `github_release`, `brew`, `http`, or `custom`.
- `version_scheme`: `semver`, `commit`, `calver`, or `opaque`.
- `latest.strategy`: `git_tags`, `git_head`, `npm_registry`, `github_release`, `brew`, `http_regex`, or `cmd`.
- `version_parse.regex` is required and must contain exactly one capture group.
- `check.file` reads local file content and parses it with `version_parse.regex`.
- API keys and token literals are rejected in command fields and stored path/source fields.
- `sync` is not part of v1.
- Command approvals are SHA-256 fingerprints of command fields and relevant cwd values.
