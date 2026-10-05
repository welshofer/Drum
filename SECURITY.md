# Security reports

Drum is an early terminal emulator. Security fixes currently target the latest source on the default branch; no older-release support schedule is promised.

Please don't put credentials, private terminal output, or detailed exploit instructions in a public issue. Private vulnerability reporting is enabled: use **Security → Report a vulnerability** on [Drum's security page](https://github.com/welshofer/Drum/security). If that option is unavailable, open an issue requesting a private contact method and include only a brief, non-sensitive description of the affected area.

For a private report, useful details include the affected commit, macOS version, a minimal reproduction, expected behavior, and the observed impact. Use synthetic terminal output and placeholder data.

Drum starts your login shell with your normal filesystem and process access. It is intentionally unsandboxed. Terminal clipboard access is opt-in, clipboard queries are rejected, and non-web links require confirmation. Appearance profiles contain data, not launch commands. Report behavior that bypasses these boundaries.
