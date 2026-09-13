find_package(SDL3 REQUIRED CONFIG)
find_package(Python3 REQUIRED COMPONENTS Interpreter)

set(FORCE_ROOT ${CMAKE_SOURCE_DIR})
set(FORCE_GEN_DIR ${CMAKE_CURRENT_SOURCE_DIR}/generated)
set(FORCE_GEN_PY ${FORCE_ROOT}/tools/gen_sdl.py)
set(FORCE_GEN_C ${FORCE_GEN_DIR}/force_data.c)
set(FORCE_GEN_H ${FORCE_GEN_DIR}/force_data.h)

file(GLOB FORCE_TMX CONFIGURE_DEPENDS "${FORCE_ROOT}/assets/maps/*.tmx")
set(FORCE_GEN_INPUTS
    ${FORCE_GEN_PY}
    ${FORCE_ROOT}/assets/tiles.txt
    ${FORCE_ROOT}/assets/missions.txt
    ${FORCE_ROOT}/assets/png/tiles.png
    ${FORCE_ROOT}/assets/maps/tiles.tsx
    ${FORCE_TMX}
)

add_custom_command(
    OUTPUT ${FORCE_GEN_C} ${FORCE_GEN_H}
    COMMAND ${Python3_EXECUTABLE} ${FORCE_GEN_PY}
            --root ${FORCE_ROOT}
            --out ${FORCE_GEN_DIR}
    DEPENDS ${FORCE_GEN_INPUTS}
    COMMENT "Generating SDL tileset and maps"
    VERBATIM
)

add_executable(force
    main.c
    core/font.c
    core/screen.c
    sdl/host.c
    sdl/input.c
    game/game.c
    ${FORCE_GEN_C}
)

target_include_directories(force PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_link_libraries(force PRIVATE SDL3::SDL3)
if(TARGET SDL3::SDL3main)
    target_link_libraries(force PRIVATE SDL3::SDL3main)
endif()

if(MSVC)
    target_compile_options(force PRIVATE /W4)
else()
    target_compile_options(force PRIVATE -Wall -Wextra -Wpedantic)
endif()
