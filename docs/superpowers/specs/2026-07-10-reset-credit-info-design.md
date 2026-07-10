# Reset Credit Information Design

## Goal

Show Codex rate-limit reset-credit information in the existing menu-bar popover
without allowing CodexQ to consume a credit. Users can see the authoritative
available count and inspect available credit details without leaving the quota
surface.

## Non-goals

- Do not call `account/rateLimitResetCredit/consume`.
- Do not render a “使用重置” button or any other credit-spending action.
- Do not add a separate refresh loop or network request.
- Do not change quota calculations, notifications, or menu-bar title behavior.

## Source Data

The existing `account/rateLimits/read` response includes an optional top-level
`rateLimitResetCredits` object:

- `availableCount`: authoritative number of available credits.
- `credits`: optional detail rows. The backend may omit this array or return
  fewer rows than `availableCount`.
- Each detail row provides `id`, `resetType`, `status`, optional `title`, and
  optional `expiresAt` as a Unix timestamp.

CodexQ will continue using the same app-server process and JSON-RPC request. The
experimental consume method is explicitly outside this feature.

## Domain Model and Decoding

`QuotaSnapshot` gains an optional `resetCredits` value so existing callers and
old cache files remain valid. The new value contains:

- `availableCount: Int`
- `credits: [ResetCredit]?`

Each `ResetCredit` contains the fields needed for display: `id`, `resetType`,
`status`, optional `title`, and optional expiry date. Protocol status and reset
type remain strings instead of closed Swift enums so a future backend value does
not break decoding. Only rows whose status is exactly `available` are shown.

`RateLimitsResponse` decodes `rateLimitResetCredits` beside the existing quota
fields. `AppServerClient` attaches it to the returned `QuotaSnapshot` before the
snapshot reaches `QuotaStore`. `SnapshotCache` persists the combined snapshot;
decoding a cache written by an older version yields `resetCredits == nil`.

## Popover Layout

When `resetCredits` is non-nil, a reset-credit section appears between the quota
rows and embedded settings. When the field is absent or null, the section and
its divider are omitted so older app-server versions keep the current layout.

The section header is always visible and contains:

- “限额重置” on the left.
- A compact “可用 N 次” badge on the right.
- A disclosure chevron.

The badge uses green when `availableCount > 0` and a secondary neutral style
when the count is zero. The whole header toggles expansion. It starts collapsed
for each view lifetime and does not add a persisted preference.

When expanded:

- Show one compact row for each `available` credit detail.
- Use the backend title when it is non-empty; otherwise show “完整额度重置” for
  `codexRateLimits` and “额度重置” for unknown reset types.
- Show “将于 M/D 到期” using the current locale when `expiresAt` is present.
- Show “无到期时间” when expiry is absent.
- If `availableCount == 0`, show “暂无可用重置”.
- If `availableCount > 0` but no available detail rows were supplied, show
  “暂无详细信息”.

The header count always comes from `availableCount`, never from the detail-row
count, because the backend may cap or omit the list. No row contains a button,
context menu, gesture, or other action that can consume a credit.

## Formatting

A focused reset-credit expiry formatter owns the short `M/d` date text and is
tested independently. The view supplies the “将于 … 到期” and “无到期时间”
labels. This avoids coupling reset-credit dates to the existing five-hour and
weekly reset formatter.

## Error and Compatibility Behavior

- Missing or null `rateLimitResetCredits`: hide the section; quota refresh still
  succeeds.
- Missing detail array: preserve and display the authoritative count.
- Unknown status: retain in the model but do not display it as available.
- Unknown reset type: use the generic fallback title.
- Old cache without the new field: decode successfully and hide the section
  until the next refresh supplies data.
- Normal app-server, timeout, and quota-decoding errors keep their current UI.

## Testing

Tests will cover:

- Decoding count, detail rows, titles, statuses, reset types, and expiry dates.
- Missing and null reset-credit data.
- Old cached snapshot compatibility.
- Filtering only `available` rows without changing `availableCount`.
- Fallback titles for missing titles and unknown reset types.
- Expiry formatting and missing-expiry copy.
- Zero-count and count-without-details display states.
- The existing full test suite, release build, signed app bundle, and live
  `account/rateLimits/read` refresh path.

## Success Criteria

- The popover shows “可用 N 次” whenever the server returns reset-credit data.
- Expanding the section shows only available details and their expiry state.
- CodexQ never sends a consume request.
- Existing quota display, old caches, and older app-server responses continue to
  work unchanged.
