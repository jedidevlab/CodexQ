# CodexQ release workflow

When publishing a CodexQ release, verify the new GitHub Release and both architecture archives first. Then run `./script/install_release.sh dist/CodexQ-<version>-$(uname -m).zip` on this Mac. Finish only after the installed app reports the release version and its process runs from `/Applications/CodexQ.app` or `~/Applications/CodexQ.app`. The installer replaces only the app bundle; user settings and history stay in their existing locations.

Before pushing source or publishing a Release, inspect the diff, release notes, screenshots, and any logs or diagnostics for personal information. Redact credentials, auth files, account and device identifiers, email addresses, and absolute home paths from public material. Keep local user data out of release archives.
