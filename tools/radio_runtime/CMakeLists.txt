# SPDX-License-Identifier: MIT
cmake_minimum_required(VERSION 3.20)
project(openrc_edgetx_smoke LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

set(EDGETX_SOURCE_DIR "" CACHE PATH "Pinned EdgeTX source checkout")
if(NOT IS_ABSOLUTE "${EDGETX_SOURCE_DIR}")
  message(FATAL_ERROR "Set EDGETX_SOURCE_DIR to an absolute pinned checkout path")
endif()

# These are the headers included by the host, not proof of the library's origin.
function(require_pinned_header relative_path expected_hash)
  set(header "${EDGETX_SOURCE_DIR}/${relative_path}")
  if(NOT EXISTS "${header}")
    message(FATAL_ERROR "Missing EdgeTX header: ${header}")
  endif()
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${header}")
  file(SHA256 "${header}" actual_hash)
  if(NOT "${actual_hash}" STREQUAL "${expected_hash}")
    message(FATAL_ERROR "Pinned EdgeTX header hash mismatch: ${relative_path}")
  endif()
endfunction()

require_pinned_header(companion/src/simulation/simulatorinterface.h 5f89a99da3fc9f061ef7fa3e0c522190d2e6f0a919a14252663a6eda46f8ac10)
require_pinned_header(companion/src/firmwares/boards.h 0ea5e0d1bf260808aae68eabcb93cc3bfc99dc423c76f7de7239494e68561878)
require_pinned_header(companion/src/firmwares/datahelpers.h 7b74a2acff2704e78ddc7b2e9a0af7993d6467b3923de1f90cd14edacaceb763)
require_pinned_header(companion/src/constants.h 603e13cd2ab969f37d4166640795884f42708bed793f5682889945ac858b421f)

find_package(Qt6 REQUIRED COMPONENTS Core SerialPort)
find_package(SDL2 2.0 REQUIRED CONFIG)
find_package(Threads REQUIRED)

add_executable(openrc-edgetx-smoke main.cpp)
target_compile_definitions(openrc-edgetx-smoke PRIVATE SDL_MAIN_HANDLED)
target_include_directories(openrc-edgetx-smoke PRIVATE
  "${EDGETX_SOURCE_DIR}/companion/src"
  "${EDGETX_SOURCE_DIR}/companion/src/simulation"
)
target_link_libraries(openrc-edgetx-smoke PRIVATE Qt6::Core Qt6::SerialPort SDL2::SDL2 Threads::Threads)
