#!/usr/bin/env bash
# =============================================================================
# va-make — Configure, build, package, and test rocwmma (ROCm 7.13 / gfx1103)
#
# Usage:
#   ./va-make [options] <command>
#
# Commands:
#   build       Configure + build (headers + cmake export files)
#   package     Configure + build + produce .deb/.rpm/.tar.gz packages
#   test        Configure + build (with tests) + run test suite
#   clean       Remove the build directory
#
# Options:
#   --rocm-path <path>      ROCm root            (default: /opt/rocm)
#   --gpu-targets <targets> Semicolon-separated  (default: gfx1103)
#   --build-dir <path>      Build tree           (default: build/release)
#   --prefix <path>         Install prefix       (default: /opt/rocwmma-rocm7.13)
#   --build-type <type>     Release|Debug|RelWithDebInfo  (default: Release)
#   --jobs <n>              Parallel jobs        (default: nproc)
#   --test-suite <set>      smoke|regression|extended    (default: smoke)
#   --skip-preflight        Skip prerequisite checks (not recommended)
#   --clean-first           Wipe build dir before running command
#   -h, --help              Show this help
#
# Examples:
#   ./va-make build
#   ./va-make package
#   ./va-make --build-type Debug build
#   ./va-make --test-suite regression test
#   ./va-make --clean-first package
#   ./va-make --gpu-targets "gfx1100;gfx1103" package
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
ROCM_PATH="/opt/rocm"
GPU_TARGETS="gfx1103"
BUILD_DIR="build/release"
INSTALL_PREFIX="/opt/rocwmma-rocm7.13"
BUILD_TYPE="Release"
JOBS="$(nproc)"
TEST_SUITE="smoke"
SKIP_PREFLIGHT=false
CLEAN_FIRST=false
COMMAND=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }
section() { echo -e "\n${BOLD}================================================================${RESET}"; \
            echo -e "${BOLD}  $*${RESET}"; \
            echo -e "${BOLD}================================================================${RESET}"; }

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    sed -n '/^# Usage:/,/^# ====/p' "$0" | sed 's/^# \?//'
    exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        build|package|test|clean) COMMAND="$1"; shift ;;
        --rocm-path)     ROCM_PATH="$2";     shift 2 ;;
        --gpu-targets)   GPU_TARGETS="$2";   shift 2 ;;
        --build-dir)     BUILD_DIR="$2";     shift 2 ;;
        --prefix)        INSTALL_PREFIX="$2"; shift 2 ;;
        --build-type)    BUILD_TYPE="$2";    shift 2 ;;
        --jobs)          JOBS="$2";          shift 2 ;;
        --test-suite)    TEST_SUITE="$2";    shift 2 ;;
        --skip-preflight) SKIP_PREFLIGHT=true; shift ;;
        --clean-first)   CLEAN_FIRST=true;   shift ;;
        -h|--help)       usage ;;
        *) die "Unknown argument: $1  (run with --help for usage)" ;;
    esac
done

[[ -z "$COMMAND" ]] && { error "No command given."; echo ""; usage; }

# Resolve build dir relative to repo root
FULL_BUILD_DIR="${SCRIPT_DIR}/${BUILD_DIR}"
AMDCLANG="${ROCM_PATH}/bin/amdclang"
AMDCLANGPP="${ROCM_PATH}/bin/amdclang++"

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
check_prerequisites() {
    section "Preflight checks"
    local errors=0

    # amdclang++
    if [[ ! -x "${AMDCLANGPP}" ]]; then
        error "amdclang++ not found at ${AMDCLANGPP}"
        error "  → Set --rocm-path to your ROCm installation root"
        (( errors++ )) || true
    else
        local ver
        ver="$("${AMDCLANGPP}" --version 2>&1 | head -1)"
        ok "amdclang++: ${ver}"
    fi

    # ROCm version — look inside core-* subdirectory
    local rocm_ver_file
    rocm_ver_file="$(find "${ROCM_PATH}" -maxdepth 3 -path "*/.info/version" 2>/dev/null | head -1)"
    if [[ -z "${rocm_ver_file}" ]]; then
        warn "Cannot find ROCm version file under ${ROCM_PATH}"
        warn "  → Check: find ${ROCM_PATH} -name version -path '*/.info/*'"
    else
        local rocm_ver major minor
        rocm_ver="$(cat "${rocm_ver_file}")"
        major="$(echo "${rocm_ver}" | cut -d. -f1)"
        minor="$(echo "${rocm_ver}" | cut -d. -f2)"
        if [[ "${major}" != "7" || "${minor}" != "13" ]]; then
            error "ROCm version is ${rocm_ver} — this package requires ROCm 7.13"
            error "  → Version file: ${rocm_ver_file}"
            (( errors++ )) || true
        else
            ok "ROCm version: ${rocm_ver}"
        fi
    fi

    # HIP runtime headers — may be in a core-* subdirectory
    local hip_header
    hip_header="$(find "${ROCM_PATH}" -maxdepth 4 -name "hip_runtime.h" \
                  -path "*/include/hip/*" 2>/dev/null | grep -v llvm | head -1)"
    if [[ -z "${hip_header}" ]]; then
        error "hip_runtime.h not found under ${ROCM_PATH}"
        error "  → Install the ROCm HIP development package"
        (( errors++ )) || true
    else
        ok "HIP headers: ${hip_header}"
    fi

    # CMake
    if ! command -v cmake &>/dev/null; then
        error "cmake not found in PATH"
        (( errors++ )) || true
    else
        local cmake_ver
        cmake_ver="$(cmake --version | head -1)"
        ok "CMake: ${cmake_ver}"
    fi

    # libxml2 dev
    if pkg-config --exists libxml-2.0 2>/dev/null; then
        ok "libxml2: $(pkg-config --modversion libxml-2.0)"
    elif dpkg -s libxml2-dev &>/dev/null 2>&1; then
        ok "libxml2-dev: installed (dpkg)"
    elif [[ -f "/usr/include/libxml2/libxml/xmlversion.h" ]]; then
        ok "libxml2: headers found at /usr/include/libxml2/"
    else
        error "libxml2 development headers not found"
        error "  → sudo apt install libxml2-dev"
        (( errors++ )) || true
    fi

    # rpmbuild (warn only — not needed for .deb)
    if command -v rpmbuild &>/dev/null; then
        ok "rpmbuild: $(rpmbuild --version | head -1)"
    else
        warn "rpmbuild not found — RPM packages will be skipped by CPack"
    fi

    if [[ "${errors}" -gt 0 ]]; then
        die "${errors} prerequisite check(s) failed. Use --skip-preflight to override."
    fi
    ok "All prerequisite checks passed"
}

# ---------------------------------------------------------------------------
# cmake configure
# ---------------------------------------------------------------------------
do_configure() {
    local build_tests="${1:-OFF}"
    local build_samples="${2:-OFF}"

    section "Configure  [${BUILD_TYPE} | targets: ${GPU_TARGETS}]"
    info "Source  : ${SCRIPT_DIR}"
    info "Build   : ${FULL_BUILD_DIR}"
    info "ROCm    : ${ROCM_PATH}"
    info "Prefix  : ${INSTALL_PREFIX}"
    info "Tests   : ${build_tests}   Samples: ${build_samples}"

    mkdir -p "${FULL_BUILD_DIR}"

    CC="${AMDCLANG}" CXX="${AMDCLANGPP}" cmake \
        -S "${SCRIPT_DIR}" \
        -B "${FULL_BUILD_DIR}" \
        -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
        -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
        -DCPACK_PACKAGING_INSTALL_PREFIX="${INSTALL_PREFIX}" \
        -DGPU_TARGETS="${GPU_TARGETS}" \
        -DROCWMMA_BUILD_TESTS="${build_tests}" \
        -DROCWMMA_BUILD_SAMPLES="${build_samples}"

    ok "Configure complete"
}

# ---------------------------------------------------------------------------
# cmake build
# ---------------------------------------------------------------------------
do_build() {
    section "Build  [-j${JOBS}]"
    cmake --build "${FULL_BUILD_DIR}" -- -j"${JOBS}"
    ok "Build complete"
}

# ---------------------------------------------------------------------------
# cpack package
# ---------------------------------------------------------------------------
do_package() {
    section "Package  (CPack)"
    ( cd "${FULL_BUILD_DIR}" && cmake --build . --target package )

    echo ""
    info "Generated packages:"
    find "${FULL_BUILD_DIR}" -maxdepth 1 \
        \( -name "*.deb" -o -name "*.rpm" -o -name "*.tar.gz" -o -name "*.zip" \) \
        | sort | while read -r f; do
            printf "    %-60s  %s\n" "$(basename "$f")" "$(du -sh "$f" | cut -f1)"
        done

    ok "Packaging complete"

    local deb
    deb="$(find "${FULL_BUILD_DIR}" -maxdepth 1 -name "*.deb" | head -1)"
    if [[ -n "${deb}" ]]; then
        echo ""
        info "DEB metadata:"
        dpkg-deb --info "${deb}" | grep -E "Package:|Version:|Architecture:|Depends:|Installed-Size:" \
            | sed 's/^/    /'
    fi
}

# ---------------------------------------------------------------------------
# run tests
# ---------------------------------------------------------------------------
do_test() {
    section "Tests  [suite: ${TEST_SUITE}]"
    info "Running: python3 rtest.py --emulation ${TEST_SUITE} --install_dir ${FULL_BUILD_DIR}"
    python3 "${SCRIPT_DIR}/rtest.py" \
        --emulation "${TEST_SUITE}" \
        --install_dir "${FULL_BUILD_DIR}"
    ok "Test suite complete"
}

# ---------------------------------------------------------------------------
# clean
# ---------------------------------------------------------------------------
do_clean() {
    section "Clean"
    if [[ -d "${FULL_BUILD_DIR}" ]]; then
        rm -rf "${FULL_BUILD_DIR}"
        ok "Removed ${FULL_BUILD_DIR}"
    else
        info "Nothing to clean (${FULL_BUILD_DIR} does not exist)"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Move to repo root so relative paths work regardless of where user runs from
cd "${SCRIPT_DIR}"

if [[ "${SKIP_PREFLIGHT}" == false ]]; then
    check_prerequisites
else
    warn "Skipping preflight checks (--skip-preflight)"
fi

if [[ "${CLEAN_FIRST}" == true && "${COMMAND}" != "clean" ]]; then
    do_clean
fi

case "${COMMAND}" in
    build)
        do_configure OFF OFF
        do_build
        ;;
    package)
        do_configure OFF OFF
        do_build
        do_package
        ;;
    test)
        do_configure ON OFF
        do_build
        do_test
        ;;
    clean)
        do_clean
        ;;
esac

section "Done"
ok "Command '${COMMAND}' finished successfully"
