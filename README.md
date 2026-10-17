# FORCE

FORCE is a single-player real-time strategy game for the Commodore 64 and desktop computers. You command sections of soldiers by typing orders and choosing locations with a cursor. There is no mouse control.

Version 0.1.0 has combat, bridge building, reinforcements and a campaign. Win a mission to open the next. Completed missions record your best survivor count.

Read the [user manual](MANUAL.md) for controls, commands and game rules. Its [DEVELOPER section](MANUAL.md#developer) explains Tiled maps and mission scripts.

## Current state

The first two missions "Hold the farm" and "Cross the river" have been implemented and serve as examples.  I am making this public now, because I am not enjoying the mission making aspect very much.  I may work on it from time to time, we shall see.  If anyone else improves the game or makes missions, please let me know! :)

## Build and run

You need CMake 3.20 or later, a C11 compiler, SDL3 and Python 3. On Apple Silicon, CMake finds Homebrew's SDL3 in `/opt/homebrew` automatically.

From the repository folder:

```sh
cmake -B build -S . -DCMAKE_BUILD_TYPE=Debug
cmake --build build --target force -j
./build/src/sdl/force
```

Press a key at the title screen, select a mission with Up and Down, then press RETURN. During keyboard play, use WASD or the cursor keys to move the cursor and SHIFT+letters to enter commands. F3 restarts the mission. F11 toggles fullscreen. Close the window to quit.

To run the build check:

```sh
./build/src/sdl/force --smoke
```

This checks bridge building, movement and the campaign menu, displays one frame, then exits. It requires a display.

## Commodore 64 build

You also need the `am65` assembler. CMake looks for it at `../machines/build/am65`; set `FORCE_AM65` when configuring to use another path.

```sh
cmake --build build --target force_c64
```

This creates `build/force.prg` and its data files in `build/c64`. Mount that folder as drive 8 in your emulator and autorun `build/force.prg`.

To create a disk image, install `c1541` or set `C1541` to its path, then run:

```sh
cmake --build build --target disk
```

Mount `build/force.d64` as drive 8, enter `LOAD "FORCE",8,1`, then `RUN`.

## Project documentation

- [User manual](MANUAL.md): how to play the current game.
- [Agent instructions](agents/README.md): source layout and implementation notes.
- [Build checks](agents/testing.md): verification instructions.
- [Game design](doc/README.md): intended rules, including features not yet implemented.
- [Code designs](design/README.md): proposed implementation changes.
