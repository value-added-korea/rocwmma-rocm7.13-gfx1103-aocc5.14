#!/usr/bin/env bash
# ##############################################################################
# Copyright (C) 2021-2025 Advanced Micro Devices, Inc. All rights reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ##############################################################################

# rocWMMA build and install helper for ROCm 7.13 / gfx1103 (RDNA3 iGPU) / AOCC 5.14.
#
# This is a targeted "band-aid" package: ROCm 7.13 does not ship rocwmma,
# so this script installs it to /opt/rocwmma-rocm7.13 and creates softlinks
# into /opt/rocm (and /opt/rocm-dev if present) so llama.cpp and other
# consumers find the headers automatically.
#
# Usage:
#   ./install.sh             -- configure and build the library (release mode)
#   ./install.sh -i          -- build + install to /opt/rocwmma-rocm7.13 + create ROCm symlinks
#   ./install.sh -b          -- build + generate .deb package only (no system install)
#   ./install.sh --help      -- show full usage

set -euo pipefail

ROCWMMA_SRC_PATH="$(cd "$(dirname "$(readlink -m "$0")")" && pwd)"

# ---------------------------------------------------------------------------
# Required stack versions (hard gate on preflight)
# ---------------------------------------------------------------------------
REQUIRED_ROCM_MAJOR=7
REQUIRED_ROCM_MINOR=13

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
check_exit_code() {
    if (( $1 != 0 )); then
        echo "ERROR: command exited with code $1" >&2
        exit "$1"
    fi
}

elevate_if_not_root() {
    if (( "$(id -u)" != 0 )); then
        sudo "$@"
    else
        "$@"
    fi
    check_exit_code "$?"
}

display_help() {
cat <<EOF

  rocWMMA library build & install helper.
  Target stack: ROCm ${REQUIRED_ROCM_MAJOR}.${REQUIRED_ROCM_MINOR} / gfx1103 (RDNA3 iGPU) / AOCC 5.14

  Usage:
    $0 [options]

  Options:
    -h, --help                    Print this help message.

    -i, --install                 Build, install to /opt/rocwmma-rocm7.13, and create
                                  softlinks in /opt/rocm[/rocm-dev]/include/rocwmma.

    -b, --build                   Generate the .deb package via CPack but do NOT
                                  install it. The .deb file is left in the build
                                  directory.

    -g, --debug                   Build in Debug mode (default: Release).

    -k, --relwithdebinfo          Build in RelWithDebInfo mode.

    --rocm-path <path>            Path to ROCm installation.
                                  (default: /opt/rocm)

    --gpu-targets <targets>       Semicolon-separated GPU targets.
                                  (default: gfx1103  — add more RDNA3 iGPUs as needed)

    -j, --jobs <n>                Parallel build jobs. (default: nproc)

    --build-dir <path>            Build tree location. (default: \${ROCWMMA_SRC_PATH}/build)

    --prefix <path>               CMake install prefix.
                                  (default: /opt/rocwmma-rocm7.13)

    --skip-preflight              Skip the prerequisite version checks (not recommended).

  Examples:
    # Build and install, targeting only gfx1103:
    $0 -i

    # Build and install, additional RDNA3 iGPU targets:
    $0 -i --gpu-targets "gfx1103;gfx1150;gfx1151"

    # Build .deb package only (no system install):
    $0 -b

    # Debug build:
    $0 -g -i

EOF
}

# ---------------------------------------------------------------------------
# preflight: verify the required stack is in place
# ---------------------------------------------------------------------------
check_prerequisites() {
    local errors=0

    echo ""
    echo "================================================================"
    echo "  Preflight checks (ROCm ${REQUIRED_ROCM_MAJOR}.${REQUIRED_ROCM_MINOR} / AOCC 5.14 / libxml2 / HIP)"
    echo "================================================================"

    # 1. amdclang++ — existence and version
    if [[ ! -x "${amdclang_pp}" ]]; then
        echo "  [FAIL] amdclang++ not found at ${amdclang_pp}" >&2
        echo "         Set --rocm-path to your ROCm installation root." >&2
        (( errors++ ))
    else
        local ver
        ver=$("${amdclang_pp}" --version 2>&1 | head -1)
        echo "  [OK]   amdclang++: ${ver}"

        # Warn if version doesn't look like AOCC 5.14+ (format: "AMD clang version 5.14...")
        if ! echo "${ver}" | grep -qiE "(AMD clang|AOCC).*(5\.(1[4-9]|[2-9][0-9])|[6-9]\.[0-9])"; then
            echo "  [WARN] Expected AOCC 5.14+ — detected: ${ver}" >&2
            echo "         Build may still work but is untested on this compiler version." >&2
        fi
    fi

    # 2. ROCm version — must be 7.13.x
    local rocm_ver_file="${rocm_path}/.info/version"
    if [[ -f "${rocm_ver_file}" ]]; then
        local rocm_ver
        rocm_ver=$(cat "${rocm_ver_file}")
        local rocm_major rocm_minor
        rocm_major=$(echo "${rocm_ver}" | cut -d. -f1)
        rocm_minor=$(echo "${rocm_ver}" | cut -d. -f2)
        if (( rocm_major == REQUIRED_ROCM_MAJOR && rocm_minor == REQUIRED_ROCM_MINOR )); then
            echo "  [OK]   ROCm: ${rocm_ver}"
        else
            echo "  [FAIL] ROCm ${REQUIRED_ROCM_MAJOR}.${REQUIRED_ROCM_MINOR} required — found ${rocm_ver}" >&2
            echo "         This package is a band-aid specifically for ROCm ${REQUIRED_ROCM_MAJOR}.${REQUIRED_ROCM_MINOR}." >&2
            (( errors++ ))
        fi
    else
        echo "  [WARN] ${rocm_ver_file} not found — cannot verify ROCm ${REQUIRED_ROCM_MAJOR}.${REQUIRED_ROCM_MINOR}" >&2
        echo "         Proceeding; verify manually with: cat ${rocm_ver_file}" >&2
    fi

    # 3. HIP development headers
    local hip_header="${rocm_path}/include/hip/hip_runtime.h"
    if [[ -f "${hip_header}" ]]; then
        echo "  [OK]   HIP headers: ${hip_header}"
    else
        echo "  [FAIL] HIP dev headers not found at ${hip_header}" >&2
        echo "         Install the ROCm HIP development package." >&2
        (( errors++ ))
    fi

    # 4. libxml2 development library
    if pkg-config --exists libxml-2.0 2>/dev/null; then
        echo "  [OK]   libxml2: $(pkg-config --modversion libxml-2.0)"
    elif dpkg -s libxml2-dev &>/dev/null 2>&1; then
        echo "  [OK]   libxml2-dev (dpkg)"
    elif [[ -f /usr/include/libxml2/libxml/xmlversion.h ]]; then
        echo "  [OK]   libxml2 headers at /usr/include/libxml2"
    else
        echo "  [FAIL] libxml2 development headers not found" >&2
        echo "         Install: sudo apt install libxml2-dev" >&2
        (( errors++ ))
    fi

    echo ""
    if (( errors > 0 )); then
        echo "  ${errors} preflight check(s) failed. Aborting." >&2
        echo "  Use --skip-preflight to override (not recommended)." >&2
        exit 1
    fi
    echo "  All preflight checks passed."
    echo ""
}

# ---------------------------------------------------------------------------
# create softlinks into /opt/rocm and /opt/rocm-dev so consumers find headers
# ---------------------------------------------------------------------------
create_rocm_symlinks() {
    local src="${install_prefix}/include/rocwmma"
    if [[ ! -d "${src}" ]]; then
        echo "  [WARN] Install prefix ${src} not found — skipping symlinks." >&2
        return
    fi

    local link_targets=( "/opt/rocm/include/rocwmma" )
    [[ -d /opt/rocm-dev ]] && link_targets+=( "/opt/rocm-dev/include/rocwmma" )

    echo ""
    echo "================================================================"
    echo "  Creating ROCm symlinks"
    echo "================================================================"
    for target in "${link_targets[@]}"; do
        if [[ -e "${target}" && ! -L "${target}" ]]; then
            echo "  [WARN] ${target} exists and is not a symlink — skipping." >&2
        else
            elevate_if_not_root ln -sfn "${src}" "${target}"
            echo "  ${target} -> ${src}"
        fi
    done
    echo ""
}

# ---------------------------------------------------------------------------
# defaults
# ---------------------------------------------------------------------------
install_package=false
build_package=false
build_type=Release
rocm_path=/opt/rocm
gpu_targets="gfx1103"           # default: target gfx1103 (Radeon 780M/760M)
jobs=$(nproc)
build_dir="${ROCWMMA_SRC_PATH}/build"
install_prefix=/opt/rocwmma-rocm7.13
skip_preflight=false

# ---------------------------------------------------------------------------
# argument parsing
# ---------------------------------------------------------------------------
getopt -T &>/dev/null
if (( $? != 4 )); then
    echo "ERROR: need a modern version of getopt (util-linux)" >&2
    exit 1
fi

GETOPT_PARSE=$(getopt \
    --name "$0" \
    --longoptions help,install,build,debug,relwithdebinfo,rocm-path:,gpu-targets:,jobs:,build-dir:,prefix:,skip-preflight \
    --options hibgkj: \
    -- "$@") || { display_help; exit 1; }

eval set -- "${GETOPT_PARSE}"

while true; do
    case "$1" in
        -h|--help)            display_help; exit 0 ;;
        -i|--install)         install_package=true; shift ;;
        -b|--build)           build_package=true; shift ;;
        -g|--debug)           build_type=Debug; shift ;;
        -k|--relwithdebinfo)  build_type=RelWithDebInfo; shift ;;
        --rocm-path)          rocm_path="$2"; shift 2 ;;
        --gpu-targets)        gpu_targets="$2"; shift 2 ;;
        -j|--jobs)            jobs="$2"; shift 2 ;;
        --build-dir)          build_dir="$2"; shift 2 ;;
        --prefix)             install_prefix="$2"; shift 2 ;;
        --skip-preflight)     skip_preflight=true; shift ;;
        --) shift; break ;;
        *)  echo "Unexpected argument: $1" >&2; display_help; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# derived paths
# ---------------------------------------------------------------------------
amdclang="${rocm_path}/bin/amdclang"
amdclang_pp="${rocm_path}/bin/amdclang++"
full_build_dir="${build_dir}/${build_type,,}"

# ---------------------------------------------------------------------------
# preflight
# ---------------------------------------------------------------------------
if [[ "${skip_preflight}" == false ]]; then
    check_prerequisites
fi

# ---------------------------------------------------------------------------
# cmake configure
# ---------------------------------------------------------------------------
echo ""
echo "================================================================"
echo "  rocWMMA ${build_type} build"
echo "  Source  : ${ROCWMMA_SRC_PATH}"
echo "  Build   : ${full_build_dir}"
echo "  ROCm    : ${rocm_path}"
echo "  Targets : ${gpu_targets}"
echo "  Prefix  : ${install_prefix}"
echo "================================================================"
echo ""

cmake_gpu_args=()
if [[ -n "${gpu_targets}" ]]; then
    cmake_gpu_args+=( "-DGPU_TARGETS=${gpu_targets}" )
fi

rm -rf "${full_build_dir}"
mkdir -p "${full_build_dir}"

CC="${amdclang}" CXX="${amdclang_pp}" cmake \
    -S "${ROCWMMA_SRC_PATH}" \
    -B "${full_build_dir}" \
    -DCMAKE_BUILD_TYPE="${build_type}" \
    -DCMAKE_INSTALL_PREFIX="${install_prefix}" \
    -DROCWMMA_BUILD_TESTS=OFF \
    -DROCWMMA_BUILD_SAMPLES=OFF \
    "${cmake_gpu_args[@]}"
check_exit_code "$?"

# ---------------------------------------------------------------------------
# build (header-only INTERFACE target — fast, but generates version headers
# and cmake export files required for installation)
# ---------------------------------------------------------------------------
cmake --build "${full_build_dir}" -- -j"${jobs}"
check_exit_code "$?"

# ---------------------------------------------------------------------------
# install to /opt/rocwmma-rocm7.13 + create ROCm symlinks
# ---------------------------------------------------------------------------
if [[ "${install_package}" == true ]]; then
    echo ""
    echo "================================================================"
    echo "  Installing to ${install_prefix}"
    echo "================================================================"
    echo ""

    elevate_if_not_root cmake --install "${full_build_dir}" --prefix "${install_prefix}"
    check_exit_code "$?"

    create_rocm_symlinks

    echo "rocWMMA installed successfully."
    echo "  Headers    : ${install_prefix}/include/rocwmma/"
    echo "  CMake cfg  : ${install_prefix}/lib/cmake/rocwmma/"
    echo "  ROCm links : /opt/rocm/include/rocwmma -> ${install_prefix}/include/rocwmma"
fi

# ---------------------------------------------------------------------------
# build .deb package only (no system install)
# ---------------------------------------------------------------------------
if [[ "${build_package}" == true ]]; then
    echo ""
    echo "================================================================"
    echo "  Generating .deb package with CPack"
    echo "================================================================"
    echo ""

    cd "${full_build_dir}" || { echo "ERROR: build directory not found: ${full_build_dir}" >&2; exit 1; }
    cmake --build . --target package
    check_exit_code "$?"

    deb_files=( rocwmma*.deb )
    if [[ ${#deb_files[@]} -eq 0 || ! -f "${deb_files[0]}" ]]; then
        echo "ERROR: no .deb file found in ${full_build_dir}" >&2
        exit 1
    fi

    echo ""
    echo "Generated packages:"
    for f in "${deb_files[@]}"; do
        echo "  ${full_build_dir}/${f}"
        dpkg-deb --info "${f}" | grep -E "Package:|Version:|Architecture:|Installed-Size:"
        echo ""
    done
fi
