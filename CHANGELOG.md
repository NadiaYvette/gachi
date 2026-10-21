# Changelog — gachi

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project skeleton following canonical ecosystem standards (`~/src/polytropos`, `~/src/gargamelle`, `~/src/sarutahiko`).
- Core package scaffolding under `packages/gachi-core/`.
- Five physical verification gates in `bin/` (`gachi-verify`, `generate-tags`, `gachi-tagref`, `gachi-linkcheck`, `gachi-cloc`).
- CI workflows for GitHub Actions (`.github/workflows/ci.yml`) and GitLab/Framagit/Disroot (`.gitlab-ci.yml`).
- Linux kernel RFC 2822 trailer format validation via `.githooks/commit-msg` and `.gitmessage`.
- Agent advisory orientation layer (`AGENTS.md`) and symlinks.
