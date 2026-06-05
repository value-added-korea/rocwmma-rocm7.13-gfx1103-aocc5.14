# Building and Packaging rocwmma

This document covers how to configure, build, and produce installable packages
(`.deb`, `.rpm`, `.tar.gz`) for the rocwmma ROCm 7.13 / gfx1103 standalone package.

## Prerequisites

| Requirement | Version | Check |
|---|---|---|
| ROCm | 7.13 | `cat /opt/rocm/.info/version` |
| amdclang++ (AOCC) | 5.14 | `/opt/rocm/bin/amdclang++ --version` |
| CMake | ≥ 3.14 | `cmake --version` |
| HIP dev headers | (ROCm 7.13) | `ls /opt/rocm/include/hip/hip_runtime.h` |
| libxml2 dev | any | `pkg-config --modversion libxml-2.0` |
| rpmbuild | any | `rpmbuild --version` (RPM only) |

All paths below assume ROCm is installed at `/opt/rocm`. If yours differs, replace
`/opt/rocm` with your actual ROCm root in every command.

---

## Step 1 — Configure

```bash
ROCM=/opt/rocm
BUILD=build/release

CC="$ROCM/bin/amdclang" CXX="$ROCM/bin/amdclang++" \
cmake -S . -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/opt/rocwmma-rocm7.13 \
  -DGPU_TARGETS=gfx1103 \
  -DROCWMMA_BUILD_TESTS=OFF \
  -DROCWMMA_BUILD_SAMPLES=OFF
```

### What this does

- Sets the compiler to amdclang/amdclang++ from ROCm 7.13.
- Restricts GPU code to `gfx1103` (Radeon 780M/760M, Phoenix/Hawk Point).
  Drop `-DGPU_TARGETS=gfx1103` to build for all supported architectures.
- Disables tests and samples for a fast headers-only packaging build.
  Set either to `ON` if you need to build or run them (see [Running Tests](#running-tests)).
- Sets the install prefix to `/opt/rocwmma-rocm7.13` — this becomes the
  package install root inside the `.deb`/`.rpm`.

### Configure-time checks

CMake will automatically run two compile-only checks (no GPU required):

- **CheckGFX1103** — verifies `config.hpp` correctly defines `ROCWMMA_ARCH_GFX1103`,
  `ROCWMMA_ARCH_GFX11`, and `ROCWMMA_WAVE32_MODE` for `--offload-arch=gfx1103`.
  If this fails after an upstream merge, check the gfx1103 verification table in
  CLAUDE.md.
- **CheckF8** — verifies `__hip_fp8_e5m2` and `__hip_fp8_e4m3` types are available
  in the detected ROCm toolchain. Failure here means ROCm 7.13 is not installed.

---

## Step 2 — Build

```bash
cmake --build "$BUILD" -- -j$(nproc)
```

rocwmma is a header-only library (`HEADER_ONLY` in CMakeLists.txt:241). This step
generates `rocwmma-version.hpp` and the CMake export files — it does not compile
any GPU device code.

Typical build time: **under 60 seconds**.

---

## Step 3 — Package

From the build directory, invoke the `package` target:

```bash
cd "$BUILD"
cmake --build . --target package
```

CPack produces all package formats in one pass:

| File | Format | Notes |
|---|---|---|
| `rocwmma-dev_<ver>_amd64.deb` | Debian/Ubuntu | Primary — install with `dpkg -i` |
| `rocwmma-devel-<ver>.x86_64.rpm` | RPM (RHEL/SUSE) | Requires `rpmbuild` at configure time |
| `rocwmma-<ver>-Linux-devel.tar.gz` | Tarball | Manual extraction |
| `rocwmma-<ver>-Linux-devel.zip` | ZIP | Manual extraction |

### Expected warnings

The RPM generator will emit:

```
CPackRPM:Warning: CPACK_SET_DESTDIR is set (=ON) while requesting a relocatable
package: this is not supported, the package won't be relocatable.
```

This is harmless. The rocm-cmake macros enforce `CPACK_SET_DESTDIR=ON` on Linux.
All packages will install to `/opt/rocwmma-rocm7.13/` as configured.

---

## Step 4 — Install

### Debian / Ubuntu

```bash
sudo dpkg -i rocwmma-dev_*.deb
```

### RPM (RHEL / SUSE)

```bash
sudo rpm -ivh rocwmma-devel-*.rpm
```

### Manual (tarball)

```bash
sudo tar -xzf rocwmma-*-Linux-devel.tar.gz -C /
```

After installation, files land at:

```
/opt/rocwmma-rocm7.13/
  include/rocwmma/           <- headers (use this in -I flags)
  lib/cmake/rocwmma/         <- CMake find_package() config
  share/doc/rocwmma/         <- LICENSE.md
```

### ROCm symlink (consumers that look in /opt/rocm)

The package does **not** create symlinks automatically. If a consumer (e.g. llama.cpp)
expects headers at `/opt/rocm/include/rocwmma`:

```bash
sudo ln -sf /opt/rocwmma-rocm7.13/include/rocwmma /opt/rocm/include/rocwmma
# Also if /opt/rocm-dev exists:
sudo ln -sf /opt/rocwmma-rocm7.13/include/rocwmma /opt/rocm-dev/include/rocwmma
```

---

## Consumer CMake integration

After installation, downstream projects can use `find_package`:

```cmake
find_package(rocwmma REQUIRED PATHS /opt/rocwmma-rocm7.13/lib/cmake/rocwmma)
target_link_libraries(my_target PRIVATE roc::rocwmma)
```

Or, if the symlink above was created:

```cmake
find_package(rocwmma REQUIRED)
target_link_libraries(my_target PRIVATE roc::rocwmma)
```

---

## Running Tests

To build and run the test suite, reconfigure with tests enabled:

```bash
CC="$ROCM/bin/amdclang" CXX="$ROCM/bin/amdclang++" \
cmake -S . -B "$BUILD" \
  -DGPU_TARGETS=gfx1103 \
  -DROCWMMA_BUILD_TESTS=ON \
  -DROCWMMA_BUILD_SAMPLES=OFF

cmake --build "$BUILD" -- -j$(nproc)

# Smoke set (fastest)
python3 rtest.py --emulation smoke --install_dir "$BUILD"

# Full regression set
python3 rtest.py --emulation regression --install_dir "$BUILD"
```

Tests require a gfx1103 GPU and `rocminfo` to be available. The test runner
(`rtest.py`) reads `rtest.xml` and enforces per-test timeouts.

---

## Useful CMake options

| Option | Default | Effect |
|---|---|---|
| `GPU_TARGETS` | full list | Restrict targets — pass `gfx1103` to build only for this GPU |
| `ROCWMMA_BUILD_TESTS` | `ON` | Build test binaries |
| `ROCWMMA_BUILD_SAMPLES` | `ON` | Build sample programs |
| `ROCWMMA_BUILD_BENCHMARK_TESTS` | `OFF` | Build benchmark suite (requires `ROCWMMA_BUILD_TESTS=ON`) |
| `ROCWMMA_BUILD_COMMUNITY_SAMPLES` | `OFF` | Build community-contributed samples |
| `BUILD_OFFLOAD_COMPRESS` | `ON` | Compress offload bitcode |
| `CMAKE_BUILD_TYPE` | `Release` | `Debug` or `RelWithDebInfo` for development |

To change the package install prefix (affects where `.deb`/`.rpm` installs to):

```bash
cmake ... \
  -DCMAKE_INSTALL_PREFIX=/your/prefix \
  -DCPACK_PACKAGING_INSTALL_PREFIX=/your/prefix
```

Both variables must be set together or the package and manual install paths will diverge.
