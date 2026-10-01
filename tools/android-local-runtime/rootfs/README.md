# ARM64 rootfs asset entry point

The canonical builder is
`tools/android-local-runtime/builder/build-rootfs.sh`. It intentionally runs
only on Linux x86_64 because it creates a Debian ARM64 foreign tree with
`debootstrap --foreign`; it never executes ARM64 code on the build host. The
builder writes a descriptive `*.tar.gz` filename and matching manifest rather
than a magic `rootfs.tar.gz` path.

On a Windows host, use WSL2/Linux or `build-rootfs-docker.sh`. The Docker
wrapper runs the canonical builder in a pinned Debian bookworm-slim
`linux/amd64` container. The checkout is read-only at `/src`; only the
explicitly supplied output and cache directories are writable. The temporary
rootfs/work tree is `/work`, which avoids constructing the foreign tree on a
case-folding host filesystem.

Example (all generated artifacts stay under `~/Library/Caches`, never in Git):

```bash
root=/path/to/android_codex
out=/path/to/codex-rootfs-artifacts
cache=/path/to/codex-rootfs-cache
mkdir -p "$out" "$cache"

tools/android-local-runtime/rootfs/build-rootfs-docker.sh \
  --output "$out" \
  --cache "$cache" \
  -- \
  --codex-sha256 <sha256-of-the-pinned-codex-tgz>
```

For a retryable/offline build, prepopulate the cache and pass container paths
for both archives and a foreign base rootfs:

```bash
tools/android-local-runtime/rootfs/build-rootfs-docker.sh \
  --output "$out" \
  --cache "$cache" \
  -- \
  --offline \
  --base-rootfs /cache/base-rootfs \
  --node-tarball /cache/node-v24.19.0-linux-arm64.tar.xz \
  --codex-tarball /cache/openai-codex-0.157.1-linux-arm64.tgz \
  --codex-sha256 <sha256-of-the-pinned-codex-tgz>
```

`--node-sha256` defaults to the pinned Node `24.19.0` ARM64 hash; the Codex
SHA-256 remains required by the canonical builder. The builder also verifies
the Codex npm integrity, Debian snapshot, guest package set (including `jq`),
archive paths, special files, capabilities, modes, and the final manifest.
The foreign second stage and ARM64 imports remain device finalization work; a
successful host archive is not a claim that the device runtime has been
finalized.

The rootfs artifact is a separate immutable asset from the APK and must not be
checked into this repository. After generation, use the existing
`builder/stage-for-device.py` contract on a case-sensitive Linux staging
filesystem; keep `rootfs/`, `rootfs.manifest`, and `runtime.metadata` as the
device staging payload.

## Current evidence

There is no committed `rootfs.tar.gz`. Generated ARM64 rootfs archives remain
external immutable release artifacts and must be installed through the
independent app installer. Do not reuse historical `ccpocket`/Bridge rootfs
archives: they belong to the retired product route and do not satisfy the
current `io.henry.codex` manifest contract.
