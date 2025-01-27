########################################################################
# Toolchain file for building native on an Zynq ARM Cortex A9 w/ NEON
# Usage: cmake -DCMAKE_TOOLCHAIN_FILE=<this file> <source directory>
########################################################################

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)

set(CMAKE_CXX_COMPILER arm-linux-gnueabihf-g++)
set(CMAKE_C_COMPILER arm-linux-gnueabihf-gcc)
set(CMAKE_FIND_ROOT_PATH ${CMAKE_CURRENT_LIST_DIR}/../../buildroot/output/host)

set(CMAKE_CXX_FLAGS "-mcpu=cortex-a9 -mtune=cortex-a9 -mfpu=neon-fp16 -mfloat-abi=hard -ffast-math -Wno-psabi" CACHE STRING "")
set(CMAKE_C_FLAGS "${CMAKE_CXX_FLAGS}" CACHE STRING "")
