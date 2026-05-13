#!/usr/bin/env bash
# Build a flash-and-go moab-balance Pi OS image from this repository.
#
#   ./build.sh
#
# Output: image/deploy/<date>-moab-balance-lite.img.xz
#
# Requires: docker (or any Docker-compatible runtime exposing the docker CLI).
# The build itself runs entirely inside containers; nothing is installed on
# the host. First run takes ~30–45 minutes (apt downloads); subsequent runs
# reuse pi-gen's cache and finish much faster.
#
# Workflow:
#   1. Cross-compile mcumgr for the target arch (golang:1.22 container).
#   2. Stage the moab-balance source tree into stage-moab/01-install-moab/files/.
#   3. Clone (and pin) pi-gen, drop our config + stage-moab into it.
#   4. Run pi-gen's build-docker.sh.
#   5. Copy the resulting .img.xz into image/deploy/.

set -euo pipefail

IMAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${IMAGE_DIR}/.." && pwd)"
CACHE_DIR="${IMAGE_DIR}/cache"
DEPLOY_DIR="${IMAGE_DIR}/deploy"
PIGEN_DIR="${CACHE_DIR}/pi-gen"
MCUMGR_BUILD_DIR="${CACHE_DIR}/mcumgr"
STAGED_FILES_DIR="${IMAGE_DIR}/stage-moab/01-install-moab/files"

# Tag for our log lines.
TAG="[moab-image]"
log()  { printf '%s %s\n' "${TAG}" "$*"; }
warn() { printf '%s WARN: %s\n' "${TAG}" "$*" >&2; }
die()  { printf '%s ERROR: %s\n' "${TAG}" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. Pre-flight
# ---------------------------------------------------------------------------
command -v docker >/dev/null 2>&1 \
    || die "docker is not installed or not on PATH. Install Docker Desktop, Colima, OrbStack, or Rancher Desktop and try again."

docker info >/dev/null 2>&1 \
    || die "docker daemon is not running. Start Docker Desktop / Colima / OrbStack first."

# Source our config so MCUMGR_*, PIGEN_*, TARGET_GOARCH etc. are available.
# (pi-gen will source the same file later when we run its build-docker.sh.)
# shellcheck disable=SC1091
source "${IMAGE_DIR}/config"

mkdir -p "${CACHE_DIR}" "${DEPLOY_DIR}" "${MCUMGR_BUILD_DIR}"

# ---------------------------------------------------------------------------
# 1. Cross-compile mcumgr for the target arch
# ---------------------------------------------------------------------------
MCUMGR_OUT="${MCUMGR_BUILD_DIR}/mcumgr"
MCUMGR_STAMP="${MCUMGR_BUILD_DIR}/.built-${MCUMGR_REF}-${TARGET_GOARCH}-${TARGET_GOARM}"
if [[ ! -f "${MCUMGR_STAMP}" ]] || [[ ! -x "${MCUMGR_OUT}" ]]; then
    log "Cross-compiling mcumgr (${MCUMGR_REF}) for linux/${TARGET_GOARCH}..."
    rm -f "${MCUMGR_OUT}" "${MCUMGR_BUILD_DIR}"/.built-*

    docker run --rm \
        -v "${MCUMGR_BUILD_DIR}:/work" \
        -w /work \
        -e GOOS=linux \
        -e GOARCH="${TARGET_GOARCH}" \
        -e GOARM="${TARGET_GOARM}" \
        -e CGO_ENABLED=0 \
        -e MCUMGR_REPO="${MCUMGR_REPO}" \
        -e MCUMGR_REF="${MCUMGR_REF}" \
        golang:1.22 sh -ec '
            set -e
            apt-get update -qq && apt-get install -y -qq --no-install-recommends git >/dev/null
            if [ ! -d src ]; then
                git clone --quiet "${MCUMGR_REPO}" src
            fi
            git -C src fetch --quiet origin
            git -C src checkout --quiet "${MCUMGR_REF}"
            cd src
            go build -trimpath -ldflags="-s -w" -o /work/mcumgr ./mcumgr
            chmod 0755 /work/mcumgr
        '
    touch "${MCUMGR_STAMP}"
else
    log "mcumgr already built at ${MCUMGR_OUT} (skip)"
fi

# ---------------------------------------------------------------------------
# 2. Stage the source tree into stage-moab/01-install-moab/files/
# ---------------------------------------------------------------------------
log "Staging moab-balance source into stage-moab/.../files/opt/moab-balance/"
DEST_OPT="${STAGED_FILES_DIR}/opt/moab-balance"
DEST_SYSTEMD="${STAGED_FILES_DIR}/etc/systemd/system"
DEST_BIN="${STAGED_FILES_DIR}/usr/local/bin"

rm -rf "${DEST_OPT}" "${DEST_SYSTEMD}" "${DEST_BIN}"
mkdir -p "${DEST_OPT}" "${DEST_SYSTEMD}" "${DEST_BIN}"

cp -a "${REPO_DIR}/moab_balance"   "${DEST_OPT}/"
cp -a "${REPO_DIR}/firmware"       "${DEST_OPT}/"
cp    "${REPO_DIR}/pyproject.toml" "${DEST_OPT}/"
cp    "${REPO_DIR}/install.sh"     "${DEST_OPT}/"
cp    "${REPO_DIR}/LICENSE"        "${DEST_OPT}/"
cp    "${REPO_DIR}/NOTICE"         "${DEST_OPT}/"
cp    "${REPO_DIR}/README.md"      "${DEST_OPT}/"

cp "${REPO_DIR}/systemd/moab-balance.service"   "${DEST_SYSTEMD}/"
cp "${REPO_DIR}/systemd/moab-hat-flash.service" "${DEST_SYSTEMD}/"

cp "${MCUMGR_OUT}" "${DEST_BIN}/mcumgr"
chmod 0755 "${DEST_BIN}/mcumgr"

# ---------------------------------------------------------------------------
# 3. Get pi-gen at the pinned ref
# ---------------------------------------------------------------------------
if [[ ! -d "${PIGEN_DIR}/.git" ]]; then
    log "Cloning pi-gen (${PIGEN_REF})..."
    git clone --quiet "${PIGEN_REPO}" "${PIGEN_DIR}"
fi
git -C "${PIGEN_DIR}" fetch --quiet --tags origin
git -C "${PIGEN_DIR}" reset --quiet --hard "${PIGEN_REF}"
# Only wipe stuff *we* inject (stage-moab/, config). Leave pi-gen's `work/` and
# `deploy/` alone so the apt cache from a previous run is reused — that turns
# the second-and-later builds from ~30 min into a few minutes.
git -C "${PIGEN_DIR}" clean --quiet -fdx -- 'stage-moab*' 'config' 'config.local' || true

# ---------------------------------------------------------------------------
# 4. Drop our config + stage-moab into pi-gen
# ---------------------------------------------------------------------------
log "Wiring stage-moab and config into pi-gen at ${PIGEN_DIR}"
cp "${IMAGE_DIR}/config" "${PIGEN_DIR}/config"
rm -rf "${PIGEN_DIR}/stage-moab"
cp -a "${IMAGE_DIR}/stage-moab" "${PIGEN_DIR}/stage-moab"
# Make all our shell scripts executable inside the pi-gen tree.
find "${PIGEN_DIR}/stage-moab" -type f -name '*.sh' -exec chmod 0755 {} +

# Stop pi-gen at our stage by skipping later stages it might still scan.
for s in stage3 stage4 stage5; do
    [[ -d "${PIGEN_DIR}/${s}" ]] && touch "${PIGEN_DIR}/${s}/SKIP" "${PIGEN_DIR}/${s}/SKIP_IMAGES"
done

# ---------------------------------------------------------------------------
# 5. Run pi-gen
# ---------------------------------------------------------------------------
# Pi-gen's build-docker.sh refuses to start if its `pigen_work` container
# already exists (from an earlier run) unless CONTINUE=1 is passed. When the
# container is around, reuse it — that's where stage0/1/2's apt cache lives,
# and resuming saves ~30 minutes. To force a clean rebuild, run with FRESH=1.
PIGEN_CONTAINER_NAME="${PIGEN_CONTAINER_NAME:-pigen_work}"
if [[ "${FRESH:-0}" = "1" ]]; then
    if docker ps -a --filter "name=^${PIGEN_CONTAINER_NAME}$" -q | grep -q .; then
        log "FRESH=1 set → removing existing ${PIGEN_CONTAINER_NAME} container"
        docker rm -fv "${PIGEN_CONTAINER_NAME}" >/dev/null
    fi
    PIGEN_CONTINUE=0
elif docker ps -a --filter "name=^${PIGEN_CONTAINER_NAME}$" -q | grep -q .; then
    log "Reusing existing ${PIGEN_CONTAINER_NAME} container (CONTINUE=1)"
    PIGEN_CONTINUE=1
else
    PIGEN_CONTINUE=0
fi

log "Invoking pi-gen build-docker.sh (this is the long part)..."
(cd "${PIGEN_DIR}" && CONTINUE="${PIGEN_CONTINUE}" ./build-docker.sh)

# ---------------------------------------------------------------------------
# 6. Copy artefacts into image/deploy/
# ---------------------------------------------------------------------------
log "Copying artefacts to ${DEPLOY_DIR}/"
shopt -s nullglob
artefacts=( "${PIGEN_DIR}"/deploy/*.img.xz "${PIGEN_DIR}"/deploy/*.img.zip "${PIGEN_DIR}"/deploy/*.img.gz "${PIGEN_DIR}"/deploy/*.img )
shopt -u nullglob
if [[ ${#artefacts[@]} -eq 0 ]]; then
    die "pi-gen produced no image in ${PIGEN_DIR}/deploy"
fi
for f in "${artefacts[@]}"; do
    cp -v "${f}" "${DEPLOY_DIR}/"
done

log "Done. Flash one of:"
ls -lh "${DEPLOY_DIR}"
