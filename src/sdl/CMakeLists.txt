find_package(SDL3 REQUIRED CONFIG)

add_executable(force
    main.c
    core/font.c
    core/screen.c
    sdl/host.c
    sdl/input.c
    game/game.c
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
