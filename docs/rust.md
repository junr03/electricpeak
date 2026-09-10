# Rust modules

Rust is used for host-side workflows that have enough structured state,
parsing, path handling, or safety invariants to justify a compiled program.
Short command wrappers and declarative system configuration remain shell or
Nix. The goal is safer workflow code, not replacing every shell script.

## Repository layout

The repository has one Cargo workspace:

```text
rust/
├── Cargo.toml
├── Cargo.lock
├── packages.nix
└── crates/
    └── <tool-name>/
        ├── Cargo.toml
        └── src/
```

Each independently deployed program gets its own crate under `rust/crates`.
This keeps service ownership, dependencies, tests, and release changes local.
Crate names describe their domain rather than using a generic collection of
unrelated commands. Multiple binaries belong in one crate only when they share
the same domain model and are versioned and deployed together.

`rust/packages.nix` is the single packaging entry point. It pins Cargo inputs
through `Cargo.lock`, supplies runtime command dependencies, and exposes the
same derivation to NixOS modules, flake packages, and flake checks. Rust tools
are never copied to the server outside the Nix store.

## Sharing policy

Domain code starts in the crate that owns it. A shared library crate should be
introduced only after at least two deployed crates need the same abstraction
and its behavior can be specified independently.

Good candidates for a future support crate include:

- atomic JSON file replacement and file-mode preservation;
- validated relative paths and directory traversal policy;
- subprocess execution with captured, redacted diagnostics;
- common systemd unit snapshots, when two dashboards use the same schema;
- test fixtures for deterministic command adapters.

The following should remain private to their owning crate:

- workflow phase and result enums;
- command argument construction for a particular service;
- remote-provider rules and filter expressions;
- JSON structures that only look similar but have different compatibility
  promises;
- privileged mount, copy, quarantine, or deletion policy.

This avoids a broad `utils` crate and prevents unrelated services from being
coupled by accidental implementation details.

## Runtime boundaries

Rust programs replace orchestration and data modeling, not mature system
tools. Programs should invoke external tools with explicit argument arrays,
and Nix should wrap each binary with a deterministic runtime `PATH`.

Existing systemd service boundaries remain authoritative for:

- users and groups;
- state and runtime directories;
- writable paths and filesystem protection;
- credentials;
- timeouts and scheduling;
- ordering and restart behavior.

A language migration must not silently broaden any of those permissions.
Programs should accept configuration through the existing environment or
explicit arguments so a rollout does not require a simultaneous service
redesign.

## Testing

Every crate should use the smallest applicable layers:

1. Unit tests for parsing, path validation, classification, and state
   transitions.
2. Golden JSON tests for stable files consumed by dashboards or other
   services.
3. Fixture-driven subprocess tests for recorded `systemctl`, `rclone`,
   `rsync`, or `exiftool` output.
4. Nix package builds to verify the locked dependency closure and runtime
   wrapper.
5. Host integration checks for workflows that require mounts, systemd, or
   real devices.

Tests must not require production credentials or mutate production paths.
Filesystems with unusual names, invalid UTF-8, symlinks, stale caches, partial
command output, and interrupted writes should be covered when relevant.

## CI and deployment

Pull requests and pushes to `main` run the Rust workflow in
`.github/workflows/nixos.yml`:

- `cargo fmt --check`;
- Clippy over the whole workspace with warnings denied;
- workspace tests with the checked-in lock file;
- the flake's Rust package check.

The existing server-side NixOS build remains the integration gate for pull
requests. Deployment still happens only from `main`; the normal
`nixos-rebuild switch` installs the Nix-built binary and systemd unit together.
There is no separate binary-release or copy step, so rollback is a normal
NixOS generation rollback.

For behaviorally sensitive replacements, first run the old and new programs
against fixtures. When live inputs are required, run the new implementation in
shadow mode with a separate output file, compare normalized output, and switch
the existing unit only after parity is understood.
