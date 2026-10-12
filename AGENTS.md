# CodexQ release workflow

When publishing a CodexQ release, verify the new GitHub Release and both architecture archives first. Then run `./script/install_release.sh dist/CodexQ-<version>-$(uname -m).zip` on this Mac. Finish only after the installed app reports the release version and its process runs from `/Applications/CodexQ.app` or `~/Applications/CodexQ.app`. The installer replaces only the app bundle; user settings and history stay in their existing locations.
