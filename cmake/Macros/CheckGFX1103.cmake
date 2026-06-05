###############################################################################
 #
 # MIT License
 #
 # Copyright (C) 2025 Advanced Micro Devices, Inc. All rights reserved.
 #
 # Permission is hereby granted, free of charge, to any person obtaining a copy
 # of this software and associated documentation files (the "Software"), to deal
 # in the Software without restriction, including without limitation the rights
 # to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 # copies of the Software, and to permit persons to whom the Software is
 # furnished to do so, subject to the following conditions:
 #
 # The above copyright notice and this permission notice shall be included in
 # all copies or substantial portions of the Software.
 #
 # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 # IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 # FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 # AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 # LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 # OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 # SOFTWARE.
 #
 ###############################################################################

# Verifies that compiling a HIP device kernel for gfx1103 correctly defines
# ROCWMMA_ARCH_GFX1103 as non-zero. This is a compile-only check — no GPU
# hardware is required to run it.
macro(check_gfx1103_arch_macro RESULT_VAR)
  set(_check_src "${CMAKE_BINARY_DIR}/CheckGFX1103.cxx")

  # Use preprocessor #error guards that only fire in the device compilation pass
  # (where __HIP_DEVICE_COMPILE__ == 1 and ROCWMMA_DEVICE_COMPILE == 1).
  # static_assert inside __global__ bodies fires in both host and device passes,
  # so we use #if ROCWMMA_DEVICE_COMPILE to restrict checks to the device pass only.
  file(WRITE ${_check_src}
    "#include \"${CMAKE_CURRENT_SOURCE_DIR}/library/include/rocwmma/internal/config.hpp\"\n"
    "#if ROCWMMA_DEVICE_COMPILE && !ROCWMMA_ARCH_GFX1103\n"
    "#error \"ROCWMMA_ARCH_GFX1103 must be non-zero when compiling for gfx1103\"\n"
    "#endif\n"
    "#if ROCWMMA_DEVICE_COMPILE && !ROCWMMA_ARCH_GFX11\n"
    "#error \"ROCWMMA_ARCH_GFX11 umbrella must be non-zero when compiling for gfx1103\"\n"
    "#endif\n"
    "#if ROCWMMA_DEVICE_COMPILE && !ROCWMMA_WAVE32_MODE\n"
    "#error \"ROCWMMA_WAVE32_MODE must be non-zero for gfx1103\"\n"
    "#endif\n"
    "int main() { return 0; }\n"
  )

  try_compile(${RESULT_VAR}
    ${CMAKE_BINARY_DIR}
    SOURCES ${_check_src}
    COMPILE_DEFINITIONS -xhip --offload-arch=gfx1103
  )

  file(REMOVE ${_check_src})
endmacro()
