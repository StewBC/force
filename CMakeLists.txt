cmake_minimum_required(VERSION 3.20)

project(force
    VERSION 0.1.0
    DESCRIPTION "FORCE — 8-bit style RTS (SDL host)"
    LANGUAGES C
)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Homebrew's SDL3 lives here on Apple Silicon.
if(APPLE AND EXISTS "/opt/homebrew")
    list(APPEND CMAKE_PREFIX_PATH "/opt/homebrew")
endif()

add_subdirectory(src/sdl)
add_subdirectory(src/c64)
add_subdirectory(src/iigs)
