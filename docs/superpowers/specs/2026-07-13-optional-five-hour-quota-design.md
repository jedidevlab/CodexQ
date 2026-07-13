# Optional 5-hour Quota Window Design

## Goal

Keep CodexQ refreshing and presenting the weekly quota when Codex temporarily omits the 5-hour quota window.

## Scope

- Treat the weekly window as required for a valid quota snapshot.
- Treat the 5-hour window as optional.
- Preserve the current two-window presentation whenever both windows are returned.
- When the 5-hour window is absent, show `5 小时 无限制` and continue to show the weekly quota, update time, reset credits, and refresh controls.
- Use the weekly remaining percentage in the menu bar while the 5-hour window is absent.

## Non-goals

- Do not create or infer a synthetic 5-hour quota percentage.
- Do not change refresh cadence, credentials, app-server transport, reset-credit behavior, or notification settings.

## Design

`QuotaSnapshot.fiveHour` becomes optional. A response remains valid when it includes the 10,080-minute weekly window; the 300-minute window is included only if the server supplies it.

The popover conditionally renders the existing five-hour progress row. When absent, it renders a neutral unavailable row without a progress bar or reset time. The status bar uses the five-hour remaining percentage when present and otherwise falls back to the weekly remaining percentage.

## Verification

- A weekly-only response decodes into a usable snapshot with `fiveHour == nil`.
- A two-window response is unchanged.
- A response without a weekly window remains invalid.
- Tests cover the weekly status-bar fallback and the view source contains the neutral copy.
