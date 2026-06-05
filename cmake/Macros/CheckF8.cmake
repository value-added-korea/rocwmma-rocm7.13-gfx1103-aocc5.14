# Define a macro to check for the struct
macro(check_f8 RESULT_VAR)
  # Create a temporary source file
  file(WRITE ${CMAKE_BINARY_DIR}/CheckF8.cxx
    "
    #include <hip/hip_fp8.h>
    struct __hip_fp8_e5m2 e5m2;
    struct __hip_fp8_e4m3 e4m3;

    int main() { return 0; }
    "
  )

  # Locate hip_fp8.h before find_package(hip) has run.
  # On ROCm 7.13 the layout places headers under a versioned core-X.Y subdir
  # (e.g. /opt/rocm/core-7.13/include/) rather than directly under /opt/rocm/include/.
  # Use file(GLOB) to find the header anywhere under the ROCm tree.
  get_filename_component(_compiler_bin "${CMAKE_CXX_COMPILER}" DIRECTORY)
  get_filename_component(_rocm_root "${_compiler_bin}" DIRECTORY)

  file(GLOB_RECURSE _fp8_header_candidates
    "${_rocm_root}/include/hip/hip_fp8.h"
    "${_rocm_root}/*/include/hip/hip_fp8.h")
  if(_fp8_header_candidates)
    list(GET _fp8_header_candidates 0 _fp8_header)
    get_filename_component(_fp8_incdir "${_fp8_header}" DIRECTORY)   # .../hip/
    get_filename_component(_hip_include "${_fp8_incdir}" DIRECTORY)  # .../include/
  else()
    set(_hip_include "${_rocm_root}/include")  # best-effort fallback
  endif()

  try_compile(HAS_F8
    ${CMAKE_BINARY_DIR}
    SOURCES ${CMAKE_BINARY_DIR}/CheckF8.cxx
    COMPILE_DEFINITIONS -xhip
    CMAKE_FLAGS "-DINCLUDE_DIRECTORIES=${_hip_include}"
  )

  # Set the result variable
  if(HAS_F8)
    set(${RESULT_VAR} TRUE)
  else()
    set(${RESULT_VAR} FALSE)
  endif()

  # Clean up the temporary file (optional but recommended)
  file(REMOVE ${CMAKE_BINARY_DIR}/CheckF8.cxx)
endmacro()
