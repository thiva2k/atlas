# Roadmap

Atlas v1.0.0 establishes the stable architecture: a Bash engine, marker-based
ownership, lifecycle modules, self-management through `atlasctl`, and a working
Fedora engineering workstation baseline.

This roadmap is directional, not a promise of exact dates.

## v1.1 — Release hardening and contributor experience

Primary goal: make Atlas easier to trust, test, and contribute to without
changing the architecture.

Planned work:

- Keep CI green on every push and pull request.
- Add contributor issue templates and pull request review checklists.
- Expand documentation examples for module authors.
- Tighten module README consistency across Core, Development, Desktop, and Apps.
- Improve diagnostics where successful commands currently emit confusing
  warnings.
- Finish or explicitly defer placeholder application/desktop modules such as
  `apps/brave` and `desktop/kde`.
- Add more real-Fedora validation notes for supported Fedora releases.

Non-goals:

- no module contract redesign;
- no engine plugin system;
- no non-Fedora support.

## v1.2 — Workstation coverage and operational maturity

Primary goal: broaden the managed workstation while preserving Atlas'
ownership model.

Candidate work:

- Additional application modules that follow accepted RFCs.
- Stronger backup/restore operator documentation and end-to-end validation
  recipes.
- Improved self-management diagnostics for multi-checkout environments.
- Module-level recovery guidance for common broken managed states.
- Optional scheduled validation guidance for users who want periodic health
  checks.

Non-goals:

- managing user project dependencies;
- adopting external tool state automatically;
- weakening Fedora security defaults for convenience.

## v2.0 — Larger product boundaries

Primary goal: consider architecture changes only if v1 usage proves they are
necessary.

Possible themes:

- Profiles or roles for multiple workstation types.
- A formal module capability registry if convention-only discovery becomes
  insufficient.
- A richer reporting interface for machine-readable status.
- Broader OS support, if Fedora-specific assumptions can be separated without
  compromising the v1 contract.

Any v2.0 architecture change requires an RFC. The default answer remains: keep
the v1 contract until real usage proves it insufficient.
