find_package(Python3 REQUIRED COMPONENTS Interpreter)

# C64 vertical slice. am65 lives in the sibling machines repo.
set(FORCE_AM65 "${CMAKE_SOURCE_DIR}/../machines/build/am65" CACHE FILEPATH
    "am65 assembler")
set(FORCE_C64_TILES ${CMAKE_CURRENT_SOURCE_DIR}/generated/tileset.asm)
set(FORCE_C64_HOMES ${CMAKE_CURRENT_SOURCE_DIR}/generated/homes.inc)
set(FORCE_C64_CHAR ${CMAKE_CURRENT_SOURCE_DIR}/generated/charset.bin)
set(FORCE_C64_PRG ${CMAKE_BINARY_DIR}/force.prg)
set(FORCE_TITLE_BMP ${CMAKE_SOURCE_DIR}/src/c64/generated/title_bitmap.bin)
set(FORCE_TITLE_COL ${CMAKE_SOURCE_DIR}/src/c64/generated/title_colour.bin)

add_custom_command(
    OUTPUT ${FORCE_C64_TILES} ${FORCE_C64_HOMES} ${FORCE_C64_CHAR}
           ${CMAKE_BINARY_DIR}/c64/farm.prg
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tools/gen_c64.py
    DEPENDS
        ${CMAKE_SOURCE_DIR}/tools/gen_c64.py
        ${CMAKE_SOURCE_DIR}/tools/gen_sdl.py
        ${CMAKE_SOURCE_DIR}/assets/tiles.txt
        ${CMAKE_SOURCE_DIR}/assets/missions.txt
        ${CMAKE_SOURCE_DIR}/assets/properties.txt
        ${CMAKE_SOURCE_DIR}/assets/scripts/farm.txt
        ${CMAKE_SOURCE_DIR}/assets/maps/farm.tmx
        ${CMAKE_SOURCE_DIR}/assets/maps/tiles.tsx
        ${CMAKE_SOURCE_DIR}/assets/png/tiles.png
        ${CMAKE_SOURCE_DIR}/src/sdl/core/font.c
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    COMMENT "Generating C64 charset, tile tables, homes, and map bundle"
    VERBATIM
)

add_custom_command(
    OUTPUT ${FORCE_C64_PRG}
    COMMAND ${FORCE_AM65} -i ${CMAKE_CURRENT_SOURCE_DIR}/force.asm
            -o ${FORCE_C64_PRG} --prg
    DEPENDS
        ${FORCE_C64_TILES}
        ${FORCE_C64_HOMES}
        ${FORCE_C64_CHAR}
        ${CMAKE_CURRENT_SOURCE_DIR}/load.asm
        ${FORCE_AM65}
        ${CMAKE_CURRENT_SOURCE_DIR}/force.asm
        ${CMAKE_CURRENT_SOURCE_DIR}/equ.inc
        ${CMAKE_CURRENT_SOURCE_DIR}/zp.asm
        ${CMAKE_CURRENT_SOURCE_DIR}/bss.asm
        ${CMAKE_CURRENT_SOURCE_DIR}/irq.asm
        ${CMAKE_CURRENT_SOURCE_DIR}/map.asm
        ${CMAKE_CURRENT_SOURCE_DIR}/draw.asm
        ${CMAKE_CURRENT_SOURCE_DIR}/input.asm
        ${CMAKE_CURRENT_SOURCE_DIR}/game.asm
        ${CMAKE_CURRENT_SOURCE_DIR}/command.asm
        ${CMAKE_CURRENT_SOURCE_DIR}/world.asm
        ${CMAKE_CURRENT_SOURCE_DIR}/move.asm
        ${CMAKE_CURRENT_SOURCE_DIR}/combat.asm
        ${CMAKE_CURRENT_SOURCE_DIR}/title.asm
        ${FORCE_TITLE_BMP}
        ${FORCE_TITLE_COL}
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Assembling force.prg"
    VERBATIM
)

add_custom_target(force_c64 ALL DEPENDS ${FORCE_C64_PRG})

# Not ALL: c1541 is optional. `make disk` from the repo root builds this.
set(FORCE_C64_FARM ${CMAKE_BINARY_DIR}/c64/farm.prg)
set(FORCE_C64_D64 ${CMAKE_BINARY_DIR}/force.d64)
add_custom_target(disk
    COMMAND /bin/bash ${CMAKE_SOURCE_DIR}/tools/c64_disk.sh
            ${FORCE_C64_PRG} ${FORCE_C64_FARM} ${FORCE_C64_D64}
    DEPENDS ${FORCE_C64_PRG} ${FORCE_C64_FARM}
    COMMENT "Writing force.d64"
    VERBATIM
)
