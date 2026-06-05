# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

# rocwmma-rocm7.13-gfx1103-aocc5.14

## Purpose

ROCm 7.13 does not ship `rocwmma`. This is a standalone band-aid package
that provides rocwmma for AMD RDNA3 integrated GPUs (gfx1103: Radeon 780M/760M,
Phoenix / Hawk Point) compiled with AOCC 5.14 (`amdclang++`), so that
`llama.cpp` and other HIP consumers can build successfully.

This repo will expand to cover other RDNA3 iGPU targets (gfx11xx family)
over time but gfx1103 is the primary target right now.

---

## Origin — session context

This repo was created and set up in a Claude Code session on **2026-06-05**.

**Source repo:** `value-added-korea/rocm-libraries` (fork of `ROCm/rocm-libraries`)
**Extracted from:** `projects/rocwmma/` working tree at commit `97073f35d4`
  (ROCm 7.13 develop, upstream HEAD at time of extraction)

**Key commits in upstream history that are baked into this repo:**
- `b0d9fdbe93` — upstream PR #2301: initial gfx1103 support (config.hpp, constants.hpp, wmma_impl.hpp, etc.)
- `06f52290d8` — upstream PR #7602: gfx1250 support (additive, preserved gfx1103)

**The one fix applied during the session:**
- `gfx1103` was missing from `DEFAULT_GPU_TARGETS` in `CMakeLists.txt:115`
  (dropped during an upstream merge conflict resolution). It was restored.

**Files added for this standalone package (not in upstream develop):**
- `cmake/Macros/CheckGFX1103.cmake` — configure-time gate that verifies
  `ROCWMMA_ARCH_GFX1103` is correctly set by `config.hpp`

---

## Key technical facts for future sessions

### gfx1103 is present in ALL of these files — verify after any upstream merge:

| File | What to check |
|---|---|
| `library/include/rocwmma/internal/config.hpp` | `#elif defined(__gfx1103__)` block |
| `library/include/rocwmma/internal/constants.hpp` | `AMDGCN_ARCH_ID_GFX1103 = 0x1103` and `#elif ROCWMMA_ARCH_GFX1103` |
| `library/include/rocwmma/internal/wmma_impl.hpp` | `AMDGCN_ARCH_ID_GFX1103` in `enable_gfx11_t` AND `enable_gfx11_gfx12_t` |
| `library/include/rocwmma/internal/flow_control.hpp` | covered by `ROCWMMA_ARCH_GFX11` umbrella |
| `samples/common.hpp` | `deviceName.find("gfx1103")` |
| `test/hip_device.cpp` | `gfx1103` device name lookup |
| `CMakeLists.txt:115` | `gfx1103` in the `DEFAULT_GPU_TARGETS` semicolon list |

Quick verification command:
```bash
grep -rn "gfx1103" \
  library/include/rocwmma/internal/config.hpp \
  library/include/rocwmma/internal/constants.hpp \
  library/include/rocwmma/internal/wmma_impl.hpp \
  CMakeLists.txt \
  samples/common.hpp \
  test/hip_device.cpp
```

### Applying future upstream rocwmma patches

The `upstream` remote points to `ROCm/rocm-libraries`. Because upstream stores
rocwmma under `projects/rocwmma/` but this repo has it at root, use the
`-Xsubtree` strategy option when cherry-picking:

```bash
# Fetch upstream (no tags to avoid noise)
git fetch upstream --no-tags

# See rocwmma-specific commits
git log upstream/develop --oneline -- projects/rocwmma/

# Apply a specific upstream commit
git cherry-pick -x <SHA> -Xsubtree=projects/rocwmma
```

### Build workflow

```bash
ROCM=/opt/rocm   # adjust if ROCm is elsewhere
BUILD=build/release

# Configure (headers-only library; add GPU_TARGETS to restrict compile targets)
CC="$ROCM/bin/amdclang" CXX="$ROCM/bin/amdclang++" \
cmake -S . -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/opt/rocwmma-rocm7.13 \
  -DGPU_TARGETS=gfx1103 \
  -DROCWMMA_BUILD_TESTS=OFF \
  -DROCWMMA_BUILD_SAMPLES=OFF

# Build
cmake --build "$BUILD" -- -j$(nproc)

# Package as .deb
cd "$BUILD" && cmake --build . --target package
# → produces rocwmma-*.deb in build/release/

# Install the .deb
sudo dpkg -i build/release/rocwmma-*.deb
```

Package layout:
```
/opt/rocwmma-rocm7.13/
  include/rocwmma/      <- headers
  lib/cmake/rocwmma/    <- cmake config
```

**Note:** rocWMMA is header-only (`HEADER_ONLY` in CMakeLists.txt:237), so the build is fast. The `.deb` is generated via CPack. If you need RPM instead, ensure `rpmbuild` is installed and re-run `cmake --build . --target package`.

### CMake options

| Option | Default | Notes |
|---|---|---|
| `GPU_TARGETS` | full arch list (includes gfx1103) | Pass `gfx1103` to restrict targets and speed up builds |
| `ROCWMMA_BUILD_TESTS` | ON | Disable with `-DROCWMMA_BUILD_TESTS=OFF` for headers-only builds |
| `ROCWMMA_BUILD_SAMPLES` | ON | Disable for headers-only builds |
| `ROCWMMA_BUILD_BENCHMARK_TESTS` | OFF | Requires `ROCWMMA_BUILD_TESTS=ON` |
| `ROCWMMA_BUILD_COMMUNITY_SAMPLES` | OFF | Opt-in community samples |
| `BUILD_OFFLOAD_COMPRESS` | ON | Offload bitcode compression |

### Running tests

Tests require building with `ROCWMMA_BUILD_TESTS=ON`. Re-configure, then use `rtest.py`:

```bash
# Rebuild with tests enabled
CC="$ROCM/bin/amdclang" CXX="$ROCM/bin/amdclang++" \
cmake -S . -B build/release \
  -DGPU_TARGETS=gfx1103 \
  -DROCWMMA_BUILD_TESTS=ON \
  -DROCWMMA_BUILD_SAMPLES=OFF

cmake --build build/release -- -j$(nproc)

# Run smoke emulation set (fastest, subset of tests)
python3 rtest.py --emulation smoke --install_dir build/release

# Run full regression set
python3 rtest.py --emulation regression --install_dir build/release

# Run a specific test binary directly (no rtest.py)
build/release/test/unit/vector_test/rocwmma_unit_vector_test --gtest_filter='*Float16*'
```

Test categories:
- `test/unit/` — 18+ low-level unit tests (vector, layout, io_shape, pack, etc.)
- `test/gemm/` — GEMM kernel variants (naming: PGR=prefetch, LB=lookahead buffers, MP=multi-pass)
- `test/dlrm/` — DLRM dot-product kernel tests
- `test/regression/` — hipRTC integration and issue reproduction tests

`rtest.py` reads `rtest.xml`, detects VRAM via `rocminfo`, and enforces per-test timeouts.

---

## Library architecture

rocWMMA is a **header-only** C++ template library. Consumers `#include <rocwmma/rocwmma.hpp>` and the MMA kernel code is compiled into GPU device code at consumer build time (e.g., llama.cpp's HIP build).

**Public API** (`library/include/rocwmma/`):
- `rocwmma.hpp` — main API: fragment types, `load_matrix_sync`, `store_matrix_sync`, `mma_sync`
- `rocwmma_transforms.hpp` — optional layout transform operations
- `rocwmma-version.hpp` — generated by CMake from `.in` template

**Key internal headers** (`library/include/rocwmma/internal/`):
- `config.hpp` — arch detection (`__gfx1103__` → `ROCWMMA_ARCH_GFX1103`); **gfx1103 critical**
- `constants.hpp` — arch IDs and wave mode constants; **gfx1103 critical**
- `wmma_impl.hpp` — WMMA backend dispatch; **gfx1103 critical**
- `mma.hpp`, `wmma.hpp`, `mfma.hpp` — hardware backends (WMMA = gfx11/gfx12, MFMA = gfx9)
- `layout/` — fragment layout and cooperative load system
- `utility/` — `static_for.hpp`, `functional.hpp`, `algorithm.hpp`, etc.

**hipRTC constraint:** Code in `internal/` must NOT use `std::` library functions — use custom equivalents in `internal/utility/` instead. This preserves the ability to compile rocwmma kernels via HIP RTC at runtime (see `samples/hipRTC_gemm.cpp` and `test/regression/`).

---

### Troubleshooting

**CMake configure: CheckGFX1103 failure**

`cmake/Macros/CheckGFX1103.cmake` runs a compile-only check (no GPU hardware required) verifying that `config.hpp` correctly defines `ROCWMMA_ARCH_GFX1103`, `ROCWMMA_ARCH_GFX11`, and `ROCWMMA_WAVE32_MODE` when targeting `--offload-arch=gfx1103`. If it fails after an upstream merge, run the gfx1103 verification grep (see "Key technical facts" above) to find which file lost the `__gfx1103__` guard.

**Package install prefix**

`CPACK_PACKAGING_INSTALL_PREFIX` defaults to `CMAKE_INSTALL_PREFIX`. To change the `.deb`/`.rpm` install path:
```bash
cmake ... -DCMAKE_INSTALL_PREFIX=/your/path -DCPACK_PACKAGING_INSTALL_PREFIX=/your/path
```

**ROCm symlinks (post-install)**

The `.deb` does not create the `/opt/rocm/include/rocwmma` symlink automatically. If consumers need to find headers at the standard ROCm path:
```bash
sudo ln -sf /opt/rocwmma-rocm7.13/include/rocwmma /opt/rocm/include/rocwmma
```

---

### Version

`VERSION_STRING` in `CMakeLists.txt` is `2.2.1` (bumped from upstream 2.2.0
to track this ROCm 7.13 / gfx1103 fork).

---

## GitHub

- **This repo:** `value-added-korea/rocwmma-rocm7.13-gfx1103-aocc5.14`
- **Upstream source:** `ROCm/rocm-libraries` (`projects/rocwmma/`)
- **Original fork (full rocm-libraries):** `value-added-korea/rocm-libraries`
