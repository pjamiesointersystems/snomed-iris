---
project_name: 'sct'
user_name: 'Pjamieso'
date: '2026-05-13'
sections_completed: ['technology_stack', 'language_rules', 'testing_rules', 'code_quality', 'workflow_rules', 'critical_rules']
status: 'complete'
rule_count: 27
optimized_for_llm: true
---

# Project Context for AI Agents

_This file contains critical rules and patterns that AI agents must follow when implementing code in this project. Focus on unobvious details that agents might otherwise miss._

---

## Technology Stack & Versions

- **Language:** Rust 2021 edition, stable toolchain
- **Crate:** `sct-rs` v0.3.10, binary name `sct`
- **CLI framework:** clap 4 (derive mode)
- **Serialization:** serde / serde_json 1
- **Database:** rusqlite 0.39 (bundled SQLite with FTS5)
- **Columnar formats:** parquet / arrow 58
- **Filesystem:** walkdir 2
- **HTTP:** ureq 3
- **Progress:** indicatif 0.18
- **Ordered maps:** indexmap 2 (with serde feature)
- **Time:** chrono 0.4.44 (no default features; std + clock only)
- **Feature gates:**
  - `tui` → ratatui 0.28 + crossterm 0.27
  - `gui` → axum 0.7 + tokio 1
  - `full` → tui + gui

## Critical Implementation Rules

### Language-Specific Rules (Rust)

- **Error handling:** All commands return `anyhow::Result<()>`. Use `.with_context(|| ...)` for path/file context. No custom error types.
- **Main is a thin wrapper:** `src/main.rs` only does clap parsing and dispatches to `commands::*::run()`. All logic lives in `src/commands/` or library modules.
- **Command pattern:** Each subcommand has `pub struct Args` (clap derive) + `pub fn run(args: Args) -> Result<()>` in its own file under `src/commands/`.
- **Library exposure:** `src/lib.rs` re-exports `builder`, `commands`, `format`, `rf2`, `schema` so integration tests can import them without going through the CLI.
- **Schema contract:** `schema::ConceptRecord` is the stable interface between NDJSON producer and all consumers. Bump `SCHEMA_VERSION` (currently 3) for backward-incompatible changes. Use `#[serde(default)]` for additive fields.
- **Read-only DB access:** Read-side commands use `open_db_readonly()` which sets `PRAGMA query_only = ON` — never bypass this for query commands.
- **SIGPIPE:** Reset on Unix via `libc::signal` at startup. Platform-specific code uses `#[cfg(unix)]` / `#[cfg(not(unix))]` pairs.

### Testing Rules

- **Integration tests** live in `tests/` and import from the library crate (`sct_rs::*`), not binary internals.
- **No dev-dependencies** — tests rely only on the library's public API and standard assertions.
- **CI is a hard gate:** `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, and `cargo test` must all pass. Zero warnings policy.
- **All code must compile clean** under clippy with warnings-as-errors before merging.

### Code Quality & Style Rules

- **Formatting:** `cargo fmt` with default rustfmt settings — no custom overrides.
- **File organization:** One file per subcommand in `src/commands/`, registered in `src/commands/mod.rs`.
- **Shared utilities:** Common functions (e.g., `open_db_readonly`) live in `src/commands/mod.rs`.
- **Domain types:** Core types in `src/schema.rs`, RF2 parsing in `src/rf2.rs`, NDJSON building in `src/builder.rs`.
- **Feature gating:** Optional modules wrapped with `#[cfg(feature = "...")]` in both `mod.rs` and `main.rs`.
- **File naming:** `snake_case.rs`
- **Command naming:** Lowercase single-word subcommands (`ndjson`, `sqlite`, `parquet`, `tct`, `trud`).
- **Struct naming:** `PascalCase` (`ConceptRecord`, `ConceptRef`).
- **Documentation:** `//!` on library modules, `///` on public structs and CLI. Minimal inline comments — code is self-documenting.

### Development Workflow Rules

- **Main branch:** `main` — CI runs on push and PRs targeting it.
- **Commit style:** Conventional commits (e.g., `chore(deps): bump ...`, `feat:`, `fix:`).
- **CI gates:** fmt + clippy + test must pass before merge.
- **Releases:** Cross-platform binaries built via GitHub Actions (`release.yml`), published with SHA-256 checksums.
- **Distribution:** `cargo-binstall` metadata in Cargo.toml, shell install scripts (`install.sh`, `install.ps1`).
- **Docs:** MkDocs site deployed to GitHub Pages via CI.
- **Dependency management:** Dependabot configured for automated bumps.

### Critical Don't-Miss Rules

- **NDJSON is the single source of truth.** All downstream formats (SQLite, Parquet, Markdown, Arrow) are derived from it. Never create a format that bypasses NDJSON.
- **`ConceptRecord` is a contract.** Changing `schema.rs` affects every consumer. Additive fields must use `#[serde(default)]`. Bump `SCHEMA_VERSION` for breaking changes.
- **No async in core commands.** The pipeline is synchronous and single-threaded by design. Only `gui` (axum/tokio) uses async.
- **No `unwrap()` / `expect()` in commands.** Use `anyhow` context propagation for all fallible operations.
- **Stream, don't buffer.** The UK Monolith has 831k+ concepts — never load entire datasets into memory at once. Process line-by-line or in batches.
- **SCTIDs are strings.** SNOMED concept IDs are stored as `String`, not numeric types — they can be very large.
- **RF2 is tab-separated** with a specific column ordering. The parser in `src/rf2.rs` depends on exact column positions.
- **Read-only DB pragma is intentional.** `query_only = ON` prevents accidental writes in read-side commands — don't bypass it.

---

## Usage Guidelines

**For AI Agents:**

- Read this file before implementing any code
- Follow ALL rules exactly as documented
- When in doubt, prefer the more restrictive option
- Update this file if new patterns emerge

**For Humans:**

- Keep this file lean and focused on agent needs
- Update when technology stack changes
- Review periodically for outdated rules
- Remove rules that become obvious over time

Last Updated: 2026-05-13
