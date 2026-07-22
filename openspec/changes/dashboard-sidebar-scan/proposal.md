## Why

The current Dashboard has top tabs plus a separate Scan panel, while Add Selected duplicates the meaning of each scan-row checkbox. This splits navigation and makes tracking intent ambiguous.

## What Changes

- Replace the top tabs with a native left sidebar for Overview, Items, and Scan & Add.
- Route all Dashboard, Manage Items, and Scan & Add menu actions to one reusable window and its matching sidebar section.
- Keep scanning manual: selecting Scan & Add does not start a scan; the visible Scan button does.
- Remove Add Selected. Checking a row immediately registers it; unchecking disables it; checking a disabled row re-enables it.
- Move persistent helper copy into compact tooltips and accessibility labels while retaining full meaning.

## Compatibility

- There is no change to CLI stdout, JSON, JSONL, exit codes, or machine-readable schemas.
- New registrations remain untrusted.
- Unchecking never removes a recipe, approval, state, or history.
- Existing adapter operations are reused.

## Capabilities

### Modified Capabilities

- `macos-menubar`

## Impact

Impact is limited to `UpdateBarMenuBar`, `UpdateBarMenuBarApp`, and related documentation/tests.
