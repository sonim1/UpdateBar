---
name: recipe-trust
description: Work on UpdateBar's recipe schema, validation, or scan/register flows without eroding the explicit-trust boundary. Use for any change touching recipes, trust, or command execution.
---

# Recipe Trust (UpdateBar)

Product invariant: external agents (or users) may AUTHOR recipe JSON, but UpdateBar remains the validation, trust, and execution boundary. Nothing runs without explicit prior user trust. `updatebar guide agent` documents the intended agent workflow — read its output first.

Rules:
1. Validation logic lives in `UpdateBarCore` with tests; every new recipe field gets validation + a rejection test (malformed, oversized, injection-shaped values).
2. Scan flows (package-manager discovery) produce UNTRUSTED candidates only — no path from scan to execution without the user's explicit trust step. Any change shortening that path → ask first, always.
3. Update commands are data until trusted; treat recipe-supplied strings as hostile in tests (quoting, env expansion, path traversal cases).
4. stdout from recipe commands (`list`, `check`, status) is machine-consumed — shape changes follow the stdout-contract rule (approval required).
5. Gate + exercise: quality-gate, then drive the real flow with the built binary against a fixture recipe in a test home:
   register (untrusted) → attempt update (must refuse) → trust → update (runs). Paste that sequence.
