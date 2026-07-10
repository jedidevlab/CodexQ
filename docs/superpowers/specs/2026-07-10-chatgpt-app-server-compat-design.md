# ChatGPT App-Server Compatibility Design

## Problem

CodexQ currently launches `/Applications/Codex.app/Contents/Resources/codex`.
The current desktop release is installed as `/Applications/ChatGPT.app`, so the
hard-coded legacy path no longer exists and refreshes fail with
`未找到 Codex app-server`.

## Design

`AppServerClient` will keep an ordered list of executable candidates. The
default order is the current ChatGPT bundle first and the legacy Codex bundle
second. Each refresh resolves the first executable candidate at request time,
so installing or upgrading either app does not require restarting CodexQ.

Explicit test executables continue to use the existing initializer. The JSON-RPC
protocol remains unchanged because the current ChatGPT executable was verified
to accept `initialize`, `initialized`, and `account/rateLimits/read` and return a
valid quota response.

## Error Handling

If neither candidate is executable, CodexQ reports that no ChatGPT/Codex
app-server was found. Launch, timeout, server, and decoding errors keep their
current behavior.

## Tests and Documentation

Regression tests will verify current-path precedence, legacy fallback, and the
missing-executable error without depending on applications installed on the
test machine. Chinese and English requirements will name ChatGPT as the current
dependency and Codex as a legacy-compatible fallback.

The project audit also found that the development build script assembled an
unsigned app bundle around an ad-hoc-signed Swift binary. The resulting bundle
launched but failed strict code-signature verification. The development script
will mirror the release script by ad-hoc signing and verifying the completed
bundle before launch.

## Scope

The change is limited to executable discovery, the associated user-facing
missing error, local bundle validation, tests, and requirements documentation.
Unrelated UI and quota calculation behavior will not be changed.
