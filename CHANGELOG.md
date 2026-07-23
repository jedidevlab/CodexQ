# Changelog

## [1.0.17] - 2026-07-23

**Milestone:** Reliable quota data and pricing-only Token cost accounting.

- Show the plan type returned by app-server in the popover header and unify popover separators with the inset style.
- Read quota and Token activity through one app-server session. Keep the last successful Token activity and cost data visible if a refresh fails.
- Improve local Token cost parsing: skip unreadable session files, report partial data, show all included model details, and exclude models without official OpenAI API pricing from both Token totals and cost estimates.
