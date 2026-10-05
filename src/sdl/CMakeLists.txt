find_package(SDL3 REQUIRED CONFIG)
find_package(Python3 REQUIRED COMPONENTS Interpreter)

set(FORCE_ROOT ${CMAKE_SOURCE_DIR})
set(FORCE_GEN_DIR ${CMAKE_CURRENT_SOURCE_DIR}/generated)
set(FORCE_GEN_PY ${FORCE_ROOT}/tools/gen_sdl.py)
set(FORCE_GEN_C ${FORCE_GEN_DIR}/force_data.c)
set(FORCE_GEN_H ${FORCE_GEN_DIR}/force_data.h)
set(FORCE_TITLE_PY ${FORCE_ROOT}/tools/gen_title.py)
set(FORCE_TITLE_PNG ${FORCE_ROOT}/assets/png/force_title_c64.png)
set(FORCE_TITLE_C ${FORCE_GEN_DIR}/title_data.c)
set(FORCE_TITLE_H ${FORCE_GEN_DIR}/title_data.h)
set(FORCE_TITLE_BMP ${FORCE_ROOT}/src/c64/generated/title_bitmap.bin)
set(FORCE_TITLE_COL ${FORCE_ROOT}/src/c64/generated/title_colour.bin)

file(GLOB FORCE_TMX CONFIGURE_DEPENDS "${FORCE_ROOT}/assets/maps/*.tmx")
file(GLOB FORCE_SCRIPTS CONFIGURE_DEPENDS
     "${FORCE_ROOT}/assets/scripts/*.txt")
set(FORCE_GEN_INPUTS
    ${FORCE_GEN_PY}
    ${FORCE_ROOT}/assets/tiles.txt
    ${FORCE_ROOT}/assets/missions.txt
    ${FORCE_ROOT}/assets/properties.txt
    ${FORCE_ROOT}/assets/png/tiles.png
    ${FORCE_ROOT}/assets/maps/tiles.tsx
    ${FORCE_TMX}
    ${FORCE_SCRIPTS}
)

add_custom_command(
    OUTPUT ${FORCE_TITLE_C} ${FORCE_TITLE_H} ${FORCE_TITLE_BMP} ${FORCE_TITLE_COL}
    COMMAND ${Python3_EXECUTABLE} ${FORCE_TITLE_PY}
    DEPENDS ${FORCE_TITLE_PY} ${FORCE_TITLE_PNG}
    WORKING_DIRECTORY ${FORCE_ROOT}
    COMMENT "Generating C64 and SDL title splash"
    VERBATIM
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
    game/title.c
    game/menu.c
    game/command.c
    game/world.c
    ${FORCE_GEN_C}
    ${FORCE_TITLE_C}
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
