# Changelog

## 1.1.0 — 2026-09-15

### Requirements

- Require Swift 6.2 or later and enable Swift 6 language mode.
- Require environments conforming to `TaskIsolatedEnvType` to be `Sendable`.

### Concurrency

- Store environments with checked `Sendable` conformance.
- Preserve function names, argument lists, and explicit MainActor overloads.
- Let general scoped closures capture caller-local state. General async scoped and preparation functions inherit
  the caller's actor through `nonisolated(nonsending)`.
- Keep the existing recursive lock for prepared overrides and document its protection of the private registry.
