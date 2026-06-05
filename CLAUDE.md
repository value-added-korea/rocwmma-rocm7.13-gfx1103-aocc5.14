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
- `install.sh` — build + install helper with preflight checks (ROCm 7.13,
  AOCC 5.14, libxml2, HIP headers); installs to `/opt/rocwmma-rocm7.13`
  and creates softlinks into `/opt/rocm[/rocm-dev]/include/rocwmma`
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

### Build / install

```bash
# Build and install (requires ROCm 7.13 + AOCC 5.14 + libxml2)
./install.sh -i

# Build only, target gfx1103 specifically
./install.sh -b --gpu-targets gfx1103

# Skip preflight version checks (not recommended)
./install.sh -i --skip-preflight
```

Install layout:
```
/opt/rocwmma-rocm7.13/
  include/rocwmma/      <- headers
  lib/cmake/rocwmma/    <- cmake config
Softlinks:
  /opt/rocm/include/rocwmma     -> /opt/rocwmma-rocm7.13/include/rocwmma
  /opt/rocm-dev/include/rocwmma -> /opt/rocwmma-rocm7.13/include/rocwmma  (if /opt/rocm-dev exists)
```

### Version

`VERSION_STRING` in `CMakeLists.txt` is `2.2.1` (bumped from upstream 2.2.0
to track this ROCm 7.13 / gfx1103 fork).

---

## GitHub

- **This repo:** `value-added-korea/rocwmma-rocm7.13-gfx1103-aocc5.14`
- **Upstream source:** `ROCm/rocm-libraries` (`projects/rocwmma/`)
- **Original fork (full rocm-libraries):** `value-added-korea/rocm-libraries`
