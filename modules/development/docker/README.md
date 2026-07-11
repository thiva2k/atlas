# docker

**What it does:** Installs Docker CE as a rootful Fedora system service and
records Atlas ownership with a marker.

**Installs / configures:**

- Docker CE Stable repository at `/etc/yum.repos.d/docker-ce.repo`
- `docker-ce`
- `docker-ce-cli`
- `containerd.io`
- `docker-compose-plugin`
- `docker.service` enabled and started through systemd

The Docker RPM signing key is bundled as module data and validated before import;
Atlas does not download repository trust material at runtime.

**Depends on:** nothing.

Atlas owns only the installation boundary: its repository file, marker, package
intent, and service enablement. It does not own Docker workloads or user
configuration.

Atlas never manages:

- images
- containers
- volumes
- networks
- build cache
- registries
- `~/.docker`
- Compose projects
- `/var/lib/docker`
- `/etc/docker/daemon.json`
- Docker systemd drop-ins

Security defaults are deliberate. Atlas does not add the user to the `docker`
group, does not configure a TCP listener, does not write daemon policy, and does
not run workload commands such as `docker run`, `pull`, `build`, or `prune`.

`verify` succeeds when Docker is unmanaged by Atlas, detached from Atlas, or
healthy as an Atlas-managed installation. It fails only for broken
Atlas-managed state.

`backup` and `restore` are documented no-ops because Docker workloads and data
are user-owned, large, non-portable, and unsafe for Atlas to restore over a live
workstation.
