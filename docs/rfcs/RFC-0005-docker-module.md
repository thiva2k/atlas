# RFC-0005: Docker Module

| | |
|---|---|
| **Status** | Accepted |
| **Created** | 2026-07-11 |
| **Phase / order** | Phase 2 — Container infrastructure · module 4 of 16 |
| **Depends on** | Nothing — `MODULE_DEPENDS=()` |
| **Establishes** | The ownership boundary for system container infrastructure |

---

## 1. Summary

Implement `modules/development/docker` as Atlas's lifecycle manager for a
**rootful, local Docker Engine** on Fedora. Atlas installs the Docker Engine,
CLI, Compose plugin, its vendor repository definition, and enables the system
`docker.service`. It does not manage a user's workloads or grant the invoking
user root-equivalent Docker-socket access.

Docker is not a normal command-line tool. Its daemon controls a privileged host
API; a container may mount and alter the host filesystem. This RFC therefore
defines ownership before implementation. The central rule is:

> Atlas manages the engine's installation boundary, never the workloads that
> happen to run on it.

On owner acceptance, this RFC becomes normative. It defines lifecycle behavior;
it does **not** implement the Docker module.

## 2. Goals and non-goals

**Goals**

- Install a supported Docker Engine, Docker CLI, and Docker Compose plugin on
  maintained Fedora.
- Manage only the Atlas-created vendor repository definition, installation
  markers, and rootful system-service enablement.
- Make `atlas verify` distinguish valid unmanaged/pre-install state from a
  broken Atlas-managed installation.
- Provide read-only diagnostic output through the existing `atlas doctor`
  dispatch.
- Preserve Docker workloads, user configuration, and application data under all
  lifecycle operations.

**Non-goals**

- Managing images, containers, volumes, networks, build cache, registries,
  contexts, Compose projects, or application data.
- Adding any user to the `docker` group.
- Rootless Docker, Docker Desktop, Podman migration, remote daemon management,
  registry login, daemon TCP listeners, or TLS/SSH daemon configuration.
- Creating a default `/etc/docker/daemon.json`.
- Pulling or running `hello-world` as a health check.
- Implementing this RFC in the current sprint.

## 3. Supported topology and package source

### 3.1 Rootful system Docker is the only supported mode

Atlas manages Docker CE's rootful system daemon:

- `docker.service` is enabled and started through systemd.
- The expected control path is the local Unix socket
  `/var/run/docker.sock`.
- The CLI is invoked against that socket explicitly for Atlas health probes;
  `DOCKER_HOST`, a selected remote context, and user CLI configuration must not
  redirect those probes.

Rootless Docker is intentionally deferred. It is a different topology: a user
service, per-user runtime socket and data/config directories, subordinate UID/GID
ranges, a Docker context, and commonly systemd lingering. It reduces daemon
privilege but has material compatibility and operational trade-offs. Atlas must
not silently install, migrate to, or mix rootless Docker with this rootful mode.
A rootless module or mode requires a separate RFC.

### 3.2 Docker CE Stable repository

Atlas uses Docker's official Fedora Docker CE Stable RPM repository, not a
convenience script, hand-downloaded RPMs, Fedora Moby packages, or a Podman
substitution. Docker documents this repository and the package set as the
supported Fedora installation path. The repository is justified here as an
explicit vendor trust decision: it provides the Engine, Compose plugin, and
their compatible release lifecycle as one source.

The implementation must install these packages as a compatible set:

```
docker-ce
docker-ce-cli
containerd.io
docker-compose-plugin
```

Buildx is intentionally out of scope for this RFC; it is not required for the
Engine/CLI/Compose contract and must not become an incidental dependency.

Atlas will ship the canonical `docker-ce-stable` repository definition as a
module-owned static file and install it atomically at
`/etc/yum.repos.d/docker-ce.repo`. This avoids a downloaded shell script and
does not require `dnf config-manager`. The Docker module implements its own
private privileged-file writer; a reusable engine primitive would require a
separate cross-cutting RFC. The private writer validates:

1. the canonical HTTPS Docker repository URL and expected stable base URL;
2. RPM signature checking is enabled; and
3. Docker's published RPM signing-key fingerprint
   `060A 61C5 1B55 8A7F 742B 77AA C52F EB6B 621E 9F35` is the imported key.

The trusted key list and static repository definition are versioned Atlas source.
Atlas never accepts an unknown replacement key at runtime; a Docker key rotation
requires a reviewed Atlas release that updates the allowlist and acceptance tests.

`os::dnf_install` remains the package-install primitive; the private repository
writer and its privilege, atomicity, ownership, and rollback tests ship with the
Docker module. Docker's convenience script is forbidden: it is not an auditable package source,
can install unexpected dependencies or major versions, and is not designed as a
managed upgrade path.

### 3.3 Conflicts and adoption

Atlas never infers ownership from the `docker` command, package presence, a
systemd unit, a socket, or a `docker` group. With no Atlas marker, any existing
Docker CE install, Fedora Moby package, `podman-docker` shim, Docker Desktop,
rootless daemon, custom service override, daemon configuration, or container
runtime used by CRI/Kubernetes is user-owned.

`install` must refuse rather than remove, replace, adopt, or migrate that state.
The error names the detected conflict and recommends a manual migration decision.
The only exception is an Atlas `installing` marker from an earlier interrupted
Atlas run; that is ownership evidence and may be reconciled.

## 4. Ownership and state model

### 4.1 Atlas-owned state

| State | Atlas owns it when | Lifecycle |
|---|---|---|
| Docker CE repository file | Atlas created it and its recorded hash still matches | Create/verify/remove narrowly |
| Required package intent | an Atlas marker names the Docker CE package source and rootful mode | Install/verify; never uninstall packages in `remove` |
| `docker.service` enablement | Atlas marker records rootful-system mode | Enable/start on install; disable/stop only under safe remove conditions |
| Installation marker | always | Create atomically, validate, remove narrowly |
| Daemon configuration | only after a future RFC defines an exact Atlas-owned file | **Empty managed set in RFC-0005** |

Atlas owns the installation boundary, not Docker's vendor unit files, runtime
socket inode, or daemon data directories.

### 4.2 User-owned state

The following remain user-owned even if Docker was installed by Atlas:

- images, containers (running or stopped), volumes, networks, build cache, and
  containerd state;
- registry credentials, `~/.docker/`, contexts, `DOCKER_HOST`, Compose files,
  application source, and application data;
- `/var/lib/docker`, `/var/lib/containerd`, data-root overrides, and logs;
- Docker Desktop, rootless user units, user service overrides, and user daemon
  configuration;
- `/etc/docker/daemon.json`, systemd drop-ins, insecure registries, proxy
  settings, and any daemon policy Atlas did not create.

"Disposable" is not an Atlas permission class. Images and cache may be
rebuildable in theory, but can be expensive, irreplaceable in practice, or tied
to active work. Atlas never prunes, deletes, exports, backs up, restores, or
uses their presence as installation evidence.

### 4.3 Daemon configuration is deliberately empty

`/etc/docker/daemon.json` is a monolithic configuration boundary with no safe
fragment/include contract. It can also conflict with systemd daemon flags and
prevent Docker from starting. RFC-0005 therefore creates **no** default daemon
configuration and does not overwrite, merge, normalize, or adopt an existing
one.

This still defines an ownership boundary: Atlas may own a daemon configuration
only after a later RFC specifies the exact whole-file content, migration and
rollback rules, workload impact, and ownership evidence. Until then, a discovered
`daemon.json` or Docker systemd drop-in is reported by doctor as user-owned,
unsupported co-configuration; installation on a fresh, unmarked machine refuses
instead of guessing how to merge it.

### 4.4 Marker state machine

The marker is the sole installation-ownership signal:

```
absent ── install preflight succeeds ──> installing ── full validation ──> installed
                                      └── failure ───────────────────────> installing
installed ── safe module remove ──> detached ── re-enrollment preflight ──> installing
```

The marker path is:

```
$ATLAS_STATE_DIR/installed/development-docker
```

The parent directory is mode `700`; writes are atomic and mode `600`. The
versioned marker records at least `schema=1`, `state=installing|installed|detached`,
`mode=rootful-system`, package source, whether Atlas created the repository
file, and its expected hash. A pending marker is intentional: package and
systemd operations are non-transactional, so a failed run must not make `verify`
claim that Atlas never touched the machine.

Malformed, unreadable, or inconsistent markers are broken managed state and fail
verification. `install` is allowed to reconcile an `installing` marker; it must
promote it to `installed` only after every required health check succeeds.

`detached` is deliberate provenance, not installed state. It records that Atlas
left packages in place after a safe remove, so verify returns success with a
detached-state warning and install can re-enroll only after the same conflict and
configuration preflight. It prevents a safe remove from turning the next install
into an unadoptable, apparently foreign Docker installation.

## 5. Lifecycle contract

### 5.1 `check`

`check` returns `0` only for an `installed` marker whose rootful Docker CE
installation is complete: repository ownership is intact, all required packages
and commands exist, `docker.service` is enabled and active, the local socket is
a Unix socket satisfying the §5.3 predicate, and the Compose plugin reports a version. It does not
require the invoking user to have Docker-socket access: that access is
intentionally absent under the secure default.

An `installing` marker, missing component, inactive service, invalid repository
file, or invalid socket makes `check` non-zero so `install` repairs the
Atlas-owned state. A no-marker machine is likewise non-zero: `install` must
perform preflight before deciding that it is safe to claim ownership.

### 5.2 `install`

`install` is idempotent and follows this order:

1. Require Fedora and preflight for conflicting/unmanaged Docker topologies,
   rootless mode for the invoking user, user-owned daemon configuration and
   repository files, and CRI/container-runtime conflicts. On an unmarked host,
   an installed `containerd` (not `containerd.io`), `cri-o`, `kubelet`, or an
   active `containerd`, `crio`, or `kubelet` service is a refusal: installing
   Docker's `containerd.io` could alter another workload's runtime. Plain Podman
   is not itself a conflict; only `podman-docker` is a Docker-CLI collision.
2. Atomically write the `installing` marker before the first durable mutation.
3. Create or validate the Atlas-owned repository file and signing-key
   provenance.
4. Install the required package set through DNF.
5. Run `sudo systemctl enable --now docker.service`.
6. Validate the explicit local socket and daemon API using a privileged,
   non-workload probe; validate `docker compose version` separately.
7. Promote the marker atomically to `installed`.

Atlas must not run `docker run`, `pull`, `build`, `prune`, `system prune`,
`compose up`, or any workload-mutating command. It must not enable TCP listeners,
change socket modes/groups, alter firewall or iptables alternatives, disable
SELinux, add a user to `docker`, or write daemon policy.

### 5.3 `verify` and `doctor`

The current runner dispatches `atlas doctor` to `module::verify`; it has no
separate `module::doctor` hook. RFC-0005 preserves that contract rather than
adding an engine abstraction during a module RFC. Docker `verify` therefore
emits the read-only diagnostic report required by doctor.

With no marker, `verify` returns `0`: Docker absent is valid pre-install state,
and Docker present is valid unmanaged state. It logs which state it found and
never adopts it.

With a `detached` marker, `verify` also returns `0`: Atlas deliberately detached
from service/repository management while retaining provenance for a safe future
re-enrollment. It reports that state and does not assert the detached service is
healthy.

With an `installing` or `installed` marker, `verify` fails only when Atlas's
expected state is broken: marker/repository integrity, packages/CLI, Compose,
or service enablement/activity or socket type/permissions are invalid. The
probe must use the explicit Unix socket, never an ambient remote context.

The trusted-probe rules are exact:

1. `install`, after its ordinary privileged package/service work, **must** run a
   privileged local API probe.
2. `check` never requires user socket access or prompts for elevation; package,
   service, and socket predicates make it safe to skip a repeated install.
3. `verify` first tries the explicit local socket if the caller can access it.
   Otherwise it tries `sudo -n` only when credentials are already available. It
   never prompts merely to verify.
4. An API probe that runs after direct or non-interactive authorization and
   fails is broken managed state. Lack of authorization is a diagnostic warning,
   not a reason to add the user to the Docker group.

Every local API probe uses the RPM-owned `/usr/bin/docker`, a fixed safe `PATH`,
and an environment with `DOCKER_HOST`, `DOCKER_CONTEXT`, `DOCKER_CONFIG`,
`DOCKER_TLS`, `DOCKER_TLS_VERIFY`, and `DOCKER_CERT_PATH` removed. Its endpoint
is exactly `unix:///var/run/docker.sock`. The socket predicate is: a Unix socket,
owned by UID `0`, group `docker`, mode `0660` or stricter, and no permissions for
other users. This is testable and prevents PATH, context, or environment
redirection.

After Atlas installation, a newly appearing `/etc/docker/daemon.json` or
`/etc/systemd/system/docker.service.d/` is unsupported co-configuration and
fails managed verification: Atlas cannot prove a changed daemon policy remains
safe. Doctor reports the path and asks for an explicit future configuration RFC;
it never removes it. The same rule applies to detected TCP daemon listeners.

Doctor additionally reports, without repairing:

- marker state and repository ownership;
- CLI, Compose, service, socket, and local API status;
- caller socket access and Docker-group membership;
- an active rootless user daemon, Docker Desktop/Moby/Podman conflicts, or a
  user-selected remote context;
- user-owned `daemon.json` or systemd drop-ins;
- detected TCP daemon exposure, as a verification failure with TLS/SSH guidance
  rather than modification;
- service failure guidance (`journalctl -u docker`) and the Fedora iptables-nft
  diagnostic recommended by Docker's documentation.

### 5.4 `update`

`update` is an explicit no-op in this RFC. Updating a running daemon can change
workload behavior or require a restart; Atlas must not make that availability
decision implicitly. Normal Fedora patch policy remains available to the user.
A future Docker maintenance RFC may define reviewed package-update and restart
semantics.

### 5.5 `remove` (module hook only)

The platform has no `atlas remove` verb (RFC-0002 remains proposed), but the
module hook is specified and tested for future use.

`remove` is a safe detachment, not an uninstall. It must:

1. Return success with no changes when no Docker marker exists or it is already
   `detached`.
2. Refuse without changes when privileged inspection finds any containers,
   running or stopped, or when it cannot safely inspect them.
3. When no containers exist, disable and stop only the Atlas-marked
   `docker.service`, remove only the unchanged Atlas-created repository file,
   and atomically transition the marker to `detached`.

It must never uninstall packages, remove the `docker` group, delete daemon data,
images, volumes, networks, cache, containerd data, user configuration, or a
user-owned repository/configuration file. Repeated removal is a no-op.

### 5.6 `backup` and `restore`

`module::backup` and `module::restore` are documented no-op hooks returning `0`.
The marker and repository definition are reconstructable; the only nontrivial
Docker state is user-owned workload state. Backing it up would be incomplete,
non-portable, potentially huge, and dangerous to restore over a live workstation.

## 6. Security rationale

Docker's daemon is a privileged host control plane. Docker documents that a user
who controls the daemon can mount and alter the host filesystem, making Docker
group membership effectively root-equivalent. Atlas chooses:

- **No automatic Docker-group membership.** Convenience does not outweigh
  silently granting root-equivalent access. The user may knowingly choose it
  outside Atlas, or use rootless Docker after a separate design.
- **Local Unix socket only.** Atlas never configures a TCP listener. Remote
  Docker access requires an explicit user design using TLS or SSH.
- **Rootful service, no rootless mixing.** The system daemon is conventional and
  matches the required system-service ownership; rootless is a separate security
  and support model, not a compatibility flag.
- **No default daemon JSON.** Registry mirrors, insecure registries, data-root,
  storage drivers, log drivers, resource settings, and `hosts` all change
  workload behavior or security posture.
- **No workload probe.** `hello-world` mutates images, containers, and cache;
  `docker version` against the local socket is sufficient to prove the control
  plane is responsive.

SELinux remains distribution-owned and must never be disabled by Atlas. Docker's
signature verification and DNF transaction history remain the package trust and
audit trail.

## 7. Testing and acceptance strategy

### 7.1 Unit tests

Pure-Bash tests mock DNF, privileged repository writes, systemctl, RPM queries,
socket metadata, and Docker commands. They cover:

- clean no-marker Docker absence and unmanaged Docker presence: verify succeeds;
- `installing`/`installed` markers with each broken package, repository hash,
  CLI, Compose plugin, service, socket, marker, or authorized API predicate:
  verify fails; unavailable authorization is a warning;
- marker creation before mutation, promotion only after full validation, and
  recovery from every injected install failure;
- conflicting engines/rootless/user configuration, containerd/CRI/Kubernetes
  runtime state, and `podman-docker` are refused and unchanged;
- hostile Docker environment variables, PATH shadowing, world-accessible sockets,
  and a post-install daemon JSON/drop-in/TCP listener are detected safely;
- no hook adds a group member, writes `daemon.json`, changes context, opens TCP,
  or invokes a workload command;
- repeated install, check, verify, backup, restore, and module `remove` behavior,
  including detached-to-reinstall recovery;
- remove refusal with any container and zero workload mutation on every remove
  path.

### 7.2 Integration tests

Integration tests run only in a disposable Fedora VM or equivalent container-host
environment, never the developer workstation. They exercise signed repository
registration, package transactions, systemd enable/start, socket metadata, the
privileged local API probe, Compose availability, and fault recovery.

### 7.3 Fedora acceptance

On a maintained Fedora release:

1. Fresh VM: install from the verified Docker repository; confirm the service
   survives reboot, local privileged `docker version` succeeds, and `docker
   compose version` succeeds.
2. Repeat install and verify; confirm no repository/service drift and no network
   or workload command from verification.
3. Deliberately disable the service, remove a managed package, corrupt the
   repository file, and remove the socket; confirm managed verification fails
   with actionable recovery guidance.
4. Validate that an existing Docker CE install, Moby, Podman shim, Docker
   Desktop, rootless daemon, daemon JSON, or user workload is never claimed or
   modified.
5. Confirm doctor warns—but does not alter—Docker-group access and user socket
   permissions.

## 8. Rejected alternatives

| Alternative | Rejected because |
|---|---|
| Docker convenience script | Opaque provisioning path, unexpected upgrades, no durable repository ownership |
| Fedora Moby/Podman substitution | Different package/support surface; does not satisfy the defined Docker CE lifecycle |
| Automatic `usermod -aG docker $USER` | Grants root-equivalent daemon control without an explicit security decision |
| Rootless by default | Distinct user-service, UID-mapping, context, and compatibility model |
| Default `daemon.json` | No safe merge/include boundary; changes workload policy and can conflict with systemd flags |
| `hello-world` verification | Pulls an image and creates a container, violating workload ownership |
| Package uninstall in `remove` | Can disrupt user workflows and does not improve workload safety |
| Generic backup/restore of Docker data | Incomplete, non-portable, and dangerous to restore over user workloads |

## 9. Implementation roadmap and acceptance gate

Implementation may begin only after the owner accepts this RFC.
The implementation branch must:

1. Add and test Docker's private privileged repository-file writer from §3.2,
   without weakening DNF signature verification or creating a cross-cutting
   engine abstraction.
2. Replace the Docker placeholder with the lifecycle hooks in §5.
3. Add the complete unit and integration coverage in §7.
4. Update the module README, conventions, and changelog.
5. Complete Fedora acceptance and security review before release.

No Docker engine, repository, service, group, daemon configuration, or workload
change is authorized by this RFC alone until that implementation gate is passed.

## 10. Fable architecture review (2026-07-11)

Fable reviewed the draft and blocked acceptance on six issues. All were resolved
in this proposed revision; Fable approves it for owner acceptance:

1. The RFC and index remain **Proposed** until owner acceptance.
2. Repository writing is Docker-private; no unreviewed engine abstraction is
   introduced.
3. Privileged install probing, unprivileged check/verify behavior, and the
   no-prompt verification rule are explicit.
4. Trusted probe path, environment, endpoint, and socket permissions are exact.
5. CRI/containerd conflicts are refused before any Docker mutation.
6. `detached` provenance makes safe remove followed by re-install recoverable.

Fable also required strict managed verification for post-install daemon
configuration/systemd-drop-in/TCP exposure, key-rotation policy, and explicit
tests for environment, path, socket, runtime-conflict, and re-enrollment paths;
those are incorporated above.

## 11. Sources

- [Docker Engine installation on Fedora](https://docs.docker.com/engine/install/fedora/)
- [Docker Compose plugin installation](https://docs.docker.com/compose/install/linux/)
- [Docker daemon configuration and data](https://docs.docker.com/engine/daemon/)
- [Docker daemon security and socket access](https://docs.docker.com/engine/security/)
- [Docker rootless mode](https://docs.docker.com/engine/security/rootless/)
- [Fedora Moby Engine packages](https://packages.fedoraproject.org/pkgs/moby-engine/)
