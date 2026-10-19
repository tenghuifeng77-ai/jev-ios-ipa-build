# Personal IPA build for Jev iOS

Build automation for the unmodified public source at
https://github.com/jev-chat/jev-chat-jarvis-ios,
pinned to `f4b64cc655415091180e4c0573a2a82ca4319212`.
This is an independent build configuration, not an official release.

Run the **Build Jev iOS for re-signing** workflow manually. It runs the
upstream offline checks, builds both device targets, preserves the original
App Group requirements in local ad-hoc signatures, verifies the package, and
uploads an IPA with installation notes and original license notices.

The IPA needs valid Apple re-signing before installation. Both targets must
share an authorized App Group. No keys, certificates, provisioning profiles,
or private chat content are used by this workflow.

Only manual dispatch is enabled. Jobs use a standard macOS runner with a
15-minute timeout; artifacts expire after seven days. The application source
is not modified by the build.
