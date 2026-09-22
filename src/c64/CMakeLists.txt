find_package(Python3 REQUIRED COMPONENTS Interpreter)

# C64 vertical slice. am65 lives in the sibling machines repo.
set(FORCE_AM65 "${CMAKE_SOURCE_DIR}/../machines/build/am65" CACHE FILEPATH
    "am65 assembler")
set(FORCE_C64_GEN ${CMAKE_CURRENT_SOURCE_DIR}/generated/farm.asm)
set(FORCE_C64_PRG ${CMAKE_BINARY_DIR}/force.prg)

add_custom_command(
    OUTPUT ${FORCE_C64_GEN} ${CMAKE_CURRENT_SOURCE_DIR}/generated/charset.bin
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
    COMMENT "Generating C64 charset and farm tables"
    VERBATIM
)

add_custom_command(
    OUTPUT ${FORCE_C64_PRG}
    COMMAND ${FORCE_AM65} -i ${CMAKE_CURRENT_SOURCE_DIR}/force.asm
            -o ${FORCE_C64_PRG} --prg
    DEPENDS
        ${FORCE_C64_GEN}
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
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Assembling force.prg"
    VERBATIM
)

add_custom_target(force_c64 ALL DEPENDS ${FORCE_C64_PRG})
