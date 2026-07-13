# Atlas Documentation

This directory is the contributor and operator manual for Atlas.

Start here:

- [Quick Start](quick-start.md) — install and validate Atlas on Fedora.
- [Installation](installation.md) — bootstrap behavior, PATH setup, and
  self-management.
- [Architecture Overview](architecture.md) — engine, runner, modules, markers,
  hooks, and command flow.
- [Module Authoring](module-authoring.md) — how to add a module without changing
  the engine.
- [Philosophy of Atlas](philosophy.md) — the operating principles behind the
  project.
- [Roadmap](roadmap.md) — planned direction for v1.1, v1.2, and v2.0.
- [RFC Index](rfcs/README.md) — accepted and proposed design records.
- [Coding Conventions](conventions.md) — shell, secrets, state, and safety
  rules.

The architecture is frozen. If a change requires a new engine behavior, a new
module lifecycle contract, or a different ownership model, write an RFC before
implementation.
