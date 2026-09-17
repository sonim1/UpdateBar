# Templates native UI contract

## Scope and audience
Mac developers choose one of six built-in prompts, optionally customize inputs,
read the generated prompt, and copy it into their coding agent. Preserve prompt
content and approval boundaries. No commands execute from this view.

## Layout and components
Keep the existing Dashboard window and sidebar. Use a fixed vertical header:
Templates title, one-line instruction, then native category segments. The body
alone scrolls vertically. Categories contain one full-width card per template.
Each card shows SF Symbol, title, summary, a labeled Copy prompt button, boundary,
and Customize & preview disclosure. Only one editor is expanded at a time.
Expanded fields and one selectable, wrapping text preview use the full card width.
Inputs stay on one horizontally scrollable line; the preview wraps the full value.
The preview owns scrolling only for long prompt text. Category changes reset the
outer scroll to the top; entered values survive filtering and disclosure changes.

## Tokens
Native AppKit semantic colors: labelColor, secondaryLabelColor, separatorColor,
controlBackgroundColor, textBackgroundColor, controlAccentColor. No fixed theme.
SF system typography: title22 semibold, card14 semibold, body/fields13, help12,
prompt12 monospaced. Spacing4/8/12/16/20; page inset20, card inset16, radius9.
Standard labeled buttons, native focus rings, no decorative animations.

## States and accessibility
All/categorized list; collapsed/expanded card; default/customized prompt; copy
success/failure. Preserve template identifiers and accessible names. Disclosure
announces its action and state; copy feedback includes visible text, not color
alone. Keyboard users can reach disclosures, inputs, preview and copy actions.
Blank fields retain existing prompt placeholders. No new validation policy.

## Verification
Native AppKit captures at Dashboard minimum773x452 and larger1100x760 windows,
light/dark appearances, all categories, every expanded template, long input,
filter-after-scroll, copy success/failure and keyboard use. Confirm window bounds
do not grow. Browser/Lighthouse/React tooling does not apply to this native view.
No additional deferred accessibility or layout defects accepted.
