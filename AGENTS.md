# AGENTS.md

This repository owns the generic Verus-to-BPF build pipeline. Consumers own
programs, runtime contracts, trust boundaries, and any VM or loading logic.
Do not add a README.md. Toolchain and consumer documentation is in TOOLCHAIN.md.

- `dep/verus` pins upstream Verus with complete Git history. Keep it read-only.
  Its rust-toolchain.toml selects Rust; do not duplicate that version elsewhere.
- `toolchain.mk` selects tools; `Makefile` prepares Rust and builds Verus;
  `rules.mk` verifies consumer crates and compiles BPF and optional userspace.
- Keep consumer paths, crate names, and kernel locations out of defaults.
- Preserve verification before compilation and the explicit trust-boundary lint.
  Never weaken contracts or add proof escapes to make an extraction pass.
- Keep generated outputs under build/ or consumer-selected build directories.
- Run `make check` and validate a consumer build after build-rule changes.
- Imported files and their source revision are recorded in TOOLCHAIN.md.
- Use `git commit --no-gpg-sign -s`, an `(codex)` subject prefix, and 80-column
  commit-message lines. Do not load BPF programs on the development host.
