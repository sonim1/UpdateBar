## MODIFIED Requirements

### Requirement: Persistent primary menu bar surface
The application SHALL open a native popover on primary status-button activation and retain a secondary menu for advanced commands. The popover SHALL preserve selection and scroll position while refreshing and across dismissal. Only the body SHALL scroll, with a maximum 392pt by 560pt content size constrained to the current screen.

### Requirement: Explicit update and approval actions
The application SHALL separate selection, details and update execution. Only approved eligible outdated items SHALL be selected for normal execution. Inline approval SHALL display the command and working directory, require acknowledgment, and revalidate the displayed field before approval. Approval SHALL NOT execute the update.

### Requirement: Honest action progress and recovery
The application SHALL retain its prior list during checks, show item-based progress when events are available, and distinguish successful and failed results. Dismissal SHALL NOT cancel actions. Stop SHALL drain active commands without beginning queued work. Retrying SHALL recheck status and submit only failed IDs to the existing planner. Adapters without item events SHALL use an indeterminate activity message.

### Requirement: Existing application contracts
Dashboard navigation, file refresh generation gates, mutation gates, app activation policy, Sparkle, CLI machine-readable output and Core trust/execution policies SHALL remain intact.
