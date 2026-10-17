# Optional native GS/OS port; existing SDL and C64 targets are unchanged.
find_package(Python3 COMPONENTS Interpreter REQUIRED)
add_custom_target(force_iigs
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tools/iigs/build.py
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    COMMENT "Build FORCE IIgs with Golden Gate ORCA/M and package GS/OS disk"
    VERBATIM
)
