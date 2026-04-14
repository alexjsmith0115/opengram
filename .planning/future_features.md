# Future Features

Ideas captured during phase discussions. Not scoped to any phase — evaluate during milestone planning.

## Suggestion Interaction

- **Accept All** — Batch action to apply all suggestions (Harper + LLM) at once. Apply in reverse document order to avoid offset drift. Consider separate "Accept All Grammar" (Harper-only) variant.
- **Suggestion navigation hotkey** — Dedicated keyboard shortcut to cycle through suggestions (Tab was rejected as it conflicts with text editing in target apps). Needs a key that doesn't interfere with normal typing. Consider a modifier combo (e.g., Ctrl+Shift+Arrow).
- **Enter to accept in popover** — Enter key as shortcut to accept when popover is open. Removed in Phase 6 because global key monitor intercepts Enter meant for the target app. Revisit if OpenGram gains a way to scope key monitors to "popover is open" state without global interception.
- **Auto-advance after accept** — After accepting a suggestion, automatically show the popover for the next suggestion in document order for a fast review flow.
