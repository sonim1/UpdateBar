# Dashboard LLM Prompt Templates Design

## Goal

Add a `Templates` section to the native macOS Dashboard. It provides English prompts that users can customize, copy, and paste into an LLM when asking it to inspect or operate UpdateBar through the CLI.

Success means a user can find the correct prompt by task, supply only the relevant details, understand its safety boundary, and copy the completed prompt without manually editing placeholder syntax.

## Scope

The first release contains six built-in templates in three categories:

- Discover: `Inspect the CLI`, `Check updates`
- Configure: `Add an item`, `Review & approve`
- Operate: `Update approved items`, `Diagnose issues`

Templates are static application content. They are not downloaded, user-authored, persisted, or localized. The page never runs a CLI command and never sends content to an LLM.

## Dashboard Placement

`Templates` appears in the Dashboard source-list sidebar immediately after `Scan & Add` and before `Logs`. It uses the SF Symbol `text.page.badge.magnifyingglass` where available, with `doc.on.doc` as the compatibility fallback.

Selecting it replaces the content pane in the existing Dashboard window. Existing sections, menu actions, update summary behavior, and reload behavior remain unchanged.

## Page Layout

The content pane follows the existing Dashboard visual language: system colors, native controls, compact spacing, rounded system-fill surfaces, SF Symbols, and no custom visual theme.

The header contains:

- title `Templates`;
- description `Ready-to-use prompts for working with UpdateBar through an LLM.`; and
- an `All / Discover / Configure / Operate` segmented category filter.

Template cards render in a two-column grid when space permits and one column at narrower widths. Categories remain visibly separated when `All` is selected. Filtering shows only the selected category without changing field values.

Each card contains:

- SF Symbol, title, and short safety summary;
- zero to two native text fields for relevant variables;
- a non-editable, selectable prompt preview;
- a short boundary note such as `No mutations allowed` or `Confirmation required`; and
- an icon-only copy button in the top-right corner.

The copy button uses `doc.on.doc`, has tooltip and accessibility label `Copy prompt`, and briefly changes to `checkmark` after a successful copy. It writes plain text to the general pasteboard. No notification or modal appears.

## Template Variables

Fields are local to their card. Empty optional fields produce a coherent generic prompt; required-looking fields remain represented by bracketed placeholders such as `[ITEM_NAME]` or `[SYMPTOM]`. Typing updates the preview immediately. Values are held only while the Dashboard window controller exists and are not saved.

Whitespace-only input is treated as empty. User text is inserted as literal prompt text; it is never interpreted as a command by UpdateBar.

The templates accept these variables:

- `Inspect the CLI`: optional focus area and output preference.
- `Check updates`: optional item ID and output preference.
- `Add an item`: item name or ID and source URL/package.
- `Review & approve`: item ID and optional command field.
- `Update approved items`: optional item ID and scope preference.
- `Diagnose issues`: symptom/error and optional item ID.

## Prompt Safety Contract

All prompt copy is grounded in current CLI behavior and uses `updatebar guide agent` as the authoritative agent workflow where appropriate.

Read-only templates explicitly allow only inspection commands before any mutation. Mutating templates require the LLM to:

1. inspect current CLI help or the agent guide;
2. validate current state;
3. show the exact intended command and relevant target;
4. wait for explicit user confirmation before mutation; and
5. verify and summarize the result afterward.

`Review & approve` never tells the LLM to approve all fields silently. It requires review of `updatebar approvals <id> --json`, explanation of exact command fields and risk, then separate confirmation before each `updatebar approve` action.

`Update approved items` never bypasses UpdateBar trust checks and only targets already-approved outdated items. `Diagnose issues` begins with `doctor`, status, and relevant logs, asks for secret redaction, and requires approval before any configuration edit.

## Architecture

`DashboardSection` gains `.templates` in stable sidebar order. `DashboardPanelController` owns one `TemplatesViewController` and returns it from the existing section-to-controller switch. Templates do not participate in Dashboard data reloads because their data is static and view-local.

A small presentation layer defines:

- category identity and display title;
- template identity, title, symbol, safety summary, field definitions, and prompt builder; and
- copy-feedback state.

Prompt builders are pure functions from trimmed field values to strings. The view controller owns layout, text-field observation, category filtering, pasteboard writes, and transient copy feedback. No CLI service dependency is added.

## Accessibility

Every field has a visible label or accessibility label tied to its template. Prompt previews are keyboard-selectable and expose their full text. Copy buttons expose `Copy prompt for <template title>` and accessibility help describing that the prompt is copied to the clipboard.

Category selection is keyboard reachable. Focus order follows header, category filter, then cards from top-left to bottom-right. Copy success is reflected in the button label as well as the icon so VoiceOver receives the state change.

## Error Handling

Pasteboard writes are synchronous and local. If the pasteboard cannot accept the string, the copy icon changes to an error symbol and its accessibility label becomes `Could not copy prompt`; the app does not show a Dashboard error sheet.

Template rendering has no network, filesystem, CLI, or persistence failure path.

## Testing

Tests will verify:

- `Templates` has stable sidebar order, title, and symbol;
- existing menu actions still map to their current Dashboard sections;
- all six templates have stable category, title, field definitions, and non-empty prompt output;
- blank and whitespace-only values preserve documented placeholders;
- supplied values appear in the generated prompt and placeholder text is removed only for supplied fields;
- mutating prompts contain explicit confirmation and verification instructions;
- the approval prompt requires exact-field review and never instructs silent bulk approval;
- the update prompt preserves approval checks;
- the diagnose prompt requests secret redaction and read-only diagnosis first;
- category filtering preserves field values;
- copy buttons expose tooltips and accessibility labels;
- copy writes exactly the visible preview text; and
- the macOS Dashboard target builds and the full Swift test suite passes.

## Success Criteria

- `Templates` is visible in the native Dashboard sidebar.
- Six English prompts are easy to browse by category.
- Users can fill card-specific fields and see the exact text that will be copied.
- Copy uses an icon-only native button with clear tooltip, accessibility, and success feedback.
- Prompts describe real UpdateBar CLI workflows and preserve explicit approval boundaries.
- No template action executes commands, contacts an LLM, or persists user input.
