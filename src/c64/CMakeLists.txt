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

# Layout compatibility includes resident source/producer ABIs, so code edits
# regenerate records as well as assembly. Generated includes are excluded.
file(GLOB FORCE_C64_ABI_INPUTS CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/*.asm" "${CMAKE_CURRENT_SOURCE_DIR}/*.inc")
set(FORCE_C64_FORMAT_INPUTS
    ${FORCE_C64_ABI_INPUTS}
    ${CMAKE_SOURCE_DIR}/tools/c64_package.py
    ${CMAKE_SOURCE_DIR}/tools/c64_layout.py
    ${CMAKE_SOURCE_DIR}/tools/c64_missions.py
    ${CMAKE_SOURCE_DIR}/tools/c64_routes.py
    ${CMAKE_SOURCE_DIR}/tools/lzss.py)

add_custom_command(
    OUTPUT ${FORCE_C64_TILES} ${FORCE_C64_HOMES} ${FORCE_C64_CHAR}
           ${CMAKE_CURRENT_SOURCE_DIR}/generated/layout.inc
           ${CMAKE_CURRENT_SOURCE_DIR}/generated/segments.inc
           ${CMAKE_BINARY_DIR}/c64/normandy.seq
           ${CMAKE_BINARY_DIR}/c64/bastogne.seq
           ${CMAKE_BINARY_DIR}/c64/campaign.prg
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tools/gen_c64.py
            --build-dir ${CMAKE_BINARY_DIR}
    DEPENDS
        ${FORCE_C64_FORMAT_INPUTS}
        ${CMAKE_SOURCE_DIR}/assets/c64-layout.json
        ${CMAKE_SOURCE_DIR}/tools/c64_layout.py
        ${CMAKE_SOURCE_DIR}/tools/c64_missions.py
        ${CMAKE_SOURCE_DIR}/tools/lzss.py
        ${CMAKE_SOURCE_DIR}/tools/gen_c64.py
        ${CMAKE_SOURCE_DIR}/tools/c64_routes.py
        ${CMAKE_SOURCE_DIR}/tools/gen_sdl.py
        ${CMAKE_SOURCE_DIR}/assets/tiles.txt
        ${CMAKE_SOURCE_DIR}/assets/missions.txt
        ${CMAKE_SOURCE_DIR}/assets/properties.txt
        ${CMAKE_SOURCE_DIR}/assets/scripts/farm.txt
        ${CMAKE_SOURCE_DIR}/assets/scripts/cross.txt
        ${CMAKE_SOURCE_DIR}/assets/scripts/river.txt
        ${CMAKE_SOURCE_DIR}/assets/scripts/base.txt
        ${CMAKE_SOURCE_DIR}/assets/scripts/bastogne.txt
        ${CMAKE_SOURCE_DIR}/assets/scripts/ridge.txt
        ${CMAKE_SOURCE_DIR}/assets/maps/normandy.tmx
        ${CMAKE_SOURCE_DIR}/assets/maps/bastogne.tmx
        ${CMAKE_SOURCE_DIR}/assets/maps/tiles.tsx
        ${CMAKE_SOURCE_DIR}/assets/png/tiles.png
        ${CMAKE_SOURCE_DIR}/src/sdl/core/font.c
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    COMMENT "Generating C64 charset, tile tables, homes, and map bundle"
    VERBATIM
)

add_custom_command(
    BYPRODUCTS ${CMAKE_BINARY_DIR}/c64/game-image.prg ${CMAKE_BINARY_DIR}/force.sym ${CMAKE_BINARY_DIR}/force.srcmap
    OUTPUT ${FORCE_C64_PRG} ${CMAKE_BINARY_DIR}/c64/memory-report.json
           ${CMAKE_BINARY_DIR}/c64/memory-report.md ${CMAKE_BINARY_DIR}/c64/game-image.sym
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tools/c64_package.py
            --am65 ${FORCE_AM65} --build ${CMAKE_BINARY_DIR}
    DEPENDS
        ${FORCE_C64_FORMAT_INPUTS}
        ${CMAKE_SOURCE_DIR}/assets/c64-layout.json
        ${CMAKE_SOURCE_DIR}/tools/c64_layout.py
        ${CMAKE_SOURCE_DIR}/tools/c64_package.py
        ${CMAKE_SOURCE_DIR}/tools/c64_missions.py
        ${CMAKE_SOURCE_DIR}/tools/lzss.py
        ${CMAKE_CURRENT_SOURCE_DIR}/transfer.inc
        ${CMAKE_CURRENT_SOURCE_DIR}/bootstrap.asm
        ${CMAKE_CURRENT_SOURCE_DIR}/bank.asm
        ${CMAKE_CURRENT_SOURCE_DIR}/mission.asm
        ${CMAKE_CURRENT_SOURCE_DIR}/record.asm
        ${CMAKE_CURRENT_SOURCE_DIR}/validate.asm
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
        ${CMAKE_CURRENT_SOURCE_DIR}/deck.asm
        ${CMAKE_CURRENT_SOURCE_DIR}/music.asm
        ${CMAKE_CURRENT_SOURCE_DIR}/title.asm
        ${CMAKE_CURRENT_SOURCE_DIR}/menu.asm
        ${FORCE_TITLE_BMP}
        ${FORCE_TITLE_COL}
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Assembling, validating and packaging the title bootstrap and game"
    VERBATIM
)

# Chunk count follows fresh assembly. Check the manifest every build so a
# deleted or damaged supporting file cannot leave a seemingly current PRG.
add_custom_target(force_c64 ALL
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tools/c64_package.py
            --check-output --am65 ${FORCE_AM65} --build ${CMAKE_BINARY_DIR}
    DEPENDS ${FORCE_C64_PRG}
    COMMENT "Checking startup package files"
    VERBATIM)


# Not ALL: c1541 is optional. cmake --build build --target disk
set(FORCE_C64_NORMANDY ${CMAKE_BINARY_DIR}/c64/normandy.seq)
set(FORCE_C64_BASTOGNE ${CMAKE_BINARY_DIR}/c64/bastogne.seq)
set(FORCE_C64_CAMPAIGN ${CMAKE_BINARY_DIR}/c64/campaign.prg)
set(FORCE_C64_D64 ${CMAKE_BINARY_DIR}/force.d64)
add_custom_target(disk
    COMMAND /bin/bash ${CMAKE_SOURCE_DIR}/tools/c64_disk.sh
            ${FORCE_C64_D64} ${FORCE_C64_PRG}
            ${FORCE_C64_NORMANDY} normandy,s
            ${FORCE_C64_BASTOGNE} bastogne,s
            ${FORCE_C64_CAMPAIGN} campaign
            --startup ${CMAKE_BINARY_DIR}/c64/memory-report.json
    DEPENDS force_c64 ${FORCE_C64_PRG} ${FORCE_C64_NORMANDY} ${FORCE_C64_BASTOGNE}
            ${FORCE_C64_CAMPAIGN}
    COMMENT "Writing force.d64"
    VERBATIM
)
