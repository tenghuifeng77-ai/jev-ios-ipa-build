# Personal IPA build for Jev iOS

Build automation for the public source at
https://github.com/jev-chat/jev-chat-jarvis-ios,
pinned to `f4b64cc655415091180e4c0573a2a82ca4319212`.
This is an independent build configuration, not an official release.
The local patch fixes GPT-6.1 Sol requests by omitting unsupported fields,
preserving the selected reasoning effort and using a 120-second request budget.
Other providers retain their existing request parameters.

Run the **Build Jev iOS for re-signing** workflow manually. It runs the
upstream offline checks and local HTTP integration checks, builds both device targets, preserves the original
App Group requirements in local ad-hoc signatures, verifies the package, and
uploads an IPA with installation notes and original license notices.

The IPA needs valid Apple re-signing before installation. Both targets must
share an authorized App Group. No keys, certificates, provisioning profiles,
or private chat content are used by this workflow.

Only manual dispatch is enabled. Jobs use a standard macOS runner with a
15-minute timeout; artifacts expire after seven days. The application source
is changed only by the recorded patch under `patches/`. The artifact includes
the exact source diff. HTTP integration checks use dummy credentials and a
local fixture, including a 36-second response to catch the old 35-second timeout.
