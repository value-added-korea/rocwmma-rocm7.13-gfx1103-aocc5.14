# rocwmma — ROCm 7.13 / gfx1103 (RDNA3 iGPU) / AOCC 5.14

> **Band-aid package.** ROCm 7.13 does not ship `rocwmma`. This repository
> provides it as a standalone installable `.deb`/`.rpm` so that `llama.cpp`
> and other HIP consumers can build on AMD RDNA3 integrated GPUs without
> waiting for an upstream ROCm release.

## Target hardware

| GPU | Codename | APU |
|---|---|---|
| Radeon 780M / 760M | Phoenix | Ryzen 7040 series |
| Radeon 880M / 860M | Hawk Point | Ryzen 8040 series |

Architecture target: **gfx1103** (RDNA3, Wave32, WMMA instruction set).

---

## Intended use case

Install this package on a system with ROCm 7.13 and AOCC 5.14 to provide the
missing `rocwmma` headers and CMake config that the ROCm 7.13 release omitted.
After installation, HIP projects that call `find_package(rocwmma)` — such as
`llama.cpp` with `-DGGML_HIPBLAS=ON` — will find the headers automatically.

This is a **header-only** library. No GPU compilation happens during the build
of this package itself; the MMA kernel code is compiled into the *consumer*
project at its build time.

---

## Required packages

Install these before building. All three must be present; the build will check
for them and fail with a clear message if any are missing.

### 1 — ROCm 7.13

The complete ROCm 7.13 stack. Provides `amdclang++`, HIP runtime and headers,
and the rocm-cmake build tools.

```bash
# Verify
find /opt/rocm -maxdepth 3 -path "*/.info/version" | xargs cat
# Expected: 7.13.0
```

### 2 — AOCC 5.14 (amdclang++)

Shipped as part of ROCm 7.13. The compiler must be available at
`/opt/rocm/bin/amdclang++`.

```bash
# Verify
/opt/rocm/bin/amdclang++ --version
# Expected: AMD clang version 23.x.x ...
```

### 3 — libxml2 (AOCC-compatible build)

ROCm's CMake build tooling requires libxml2. The standard distro package
(`libxml2-dev`) is built with GCC and can cause link-time ABI issues when the
rest of the stack uses AOCC 5.14. Use the AOCC-compatible build from:

**[value-added-korea/libxml2\_aocc1\_amd64](git@github.com:value-added-korea/-libxml2_aocc1_amd64.git)**

```bash
# Clone and install
git clone git@github.com:value-added-korea/-libxml2_aocc1_amd64.git
cd -libxml2_aocc1_amd64
sudo dpkg -i libxml2*.deb

# Verify
pkg-config --modversion libxml-2.0
```

> **Why not `apt install libxml2-dev`?** The distro package links against
> GCC's libstdc++. Mixing that with AOCC 5.14's libc++ in the same link
> step can produce hard-to-diagnose runtime crashes or symbol resolution
> failures. The AOCC-compatible build above avoids this.

---

## Building and packaging

### Use `make.sh` — not the VSCode CMake extension

Build this project using **`make.sh`** from a terminal, not the CMake
integration in VSCode (or any IDE).

**Why:** VSCode's CMake Tools extension picks up the default system compiler
(`gcc`/`g++`) or whichever kit is selected in its UI. This project **requires**
`amdclang`/`amdclang++` from ROCm 7.13. If the wrong compiler is used, the
configure step will succeed silently but the generated headers will lack
gfx1103 support, and downstream HIP projects will fail to compile with
cryptic errors. `make.sh` enforces the correct compiler and runs preflight
checks before touching the build tree.

### Quick start

```bash
# Build + produce packages (deb, rpm, tar.gz, zip)
./make.sh package

# Build only (no packages)
./make.sh build

# Clean build tree
./make.sh clean
```

All four packages are written to `build/release/`. The primary artifact is:

```
build/release/rocwmma-dev_2.2.1-<commit>_amd64.deb
```

### Install

```bash
sudo dpkg -i build/release/rocwmma-dev_*.deb
```

Headers install to `/opt/rocwmma-rocm7.13/include/rocwmma/`.

### ROCm symlink (for consumers that look in `/opt/rocm`)

```bash
sudo ln -sf /opt/rocwmma-rocm7.13/include/rocwmma /opt/rocm/include/rocwmma
```

---

## make.sh reference

```
Usage: ./make.sh [options] <command>

Commands:
  build       Configure + build
  package     Configure + build + produce .deb/.rpm/.tar.gz/.zip
  test        Configure (tests enabled) + build + run test suite
  clean       Remove build directory

Options:
  --rocm-path <path>       ROCm root              (default: /opt/rocm)
  --gpu-targets <targets>  Semicolon-separated    (default: gfx1103)
  --build-dir <path>       Build tree             (default: build/release)
  --prefix <path>          Install prefix         (default: /opt/rocwmma-rocm7.13)
  --build-type <type>      Release|Debug|RelWithDebInfo  (default: Release)
  --jobs <n>               Parallel jobs          (default: nproc)
  --test-suite <set>       smoke|regression|extended    (default: smoke)
  --skip-preflight         Skip prerequisite checks
  --clean-first            Wipe build dir before running
  -h, --help               Show help
```

---

## Consumer CMake integration

After `dpkg -i` (and optionally creating the symlink above):

```cmake
find_package(rocwmma REQUIRED PATHS /opt/rocwmma-rocm7.13/lib/cmake/rocwmma)
target_link_libraries(my_hip_target PRIVATE roc::rocwmma)
```

---

## Version

This package is version **2.2.1**, tracking upstream `ROCm/rocm-libraries`
at commit `97073f35d4` (ROCm 7.13 develop). The version was bumped from
upstream 2.2.0 to distinguish this fork.

Upstream source: `ROCm/rocm-libraries` → `projects/rocwmma/`
