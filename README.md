# FORCE

FORCE is a single-player real-time strategy game for the Commodore 64, Apple IIgs and desktop computers. You command sections of soldiers by typing orders and choosing locations with a cursor. There is no mouse control.

YouTube video: https://youtu.be/ufk4xEnaE_I

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

## Apple IIgs build

There is now a native Apple IIgs port. It uses the same missions and C64 artwork, with a 40×25 screen using 320×200 graphics. See the [IIgs appendix](MANUAL.md#appendix-a-apple-iigs) for its controls and differences.

You need Golden Gate's `iix` command, ORCA/M and Cadius. The GS/OS disk template is included at `assets/iigs/disc/templat.2mg`. The build copies it and leaves the original unchanged. To use another template, run `python3 tools/iigs/build.py --template /path/to/template.2mg` instead of the CMake build command below.

```sh
cmake --build build --target force_iigs
python3 tools/iigs/run.py
```

The build creates `build/iigs/force.2mg`, including a pineapple-grenade Finder icon for the game. The run script launches GSSquared with a fresh private copy of that disk. You can also mount the image in the emulator yourself and boot it. Press RETURN at the title, then choose a mission and press RETURN again.

The IIgs saves campaign progress in `FORCE.STATE` on its disk. For regular play, keep a writable copy of the disk outside the build folder and reuse it. The run script starts with a fresh copy each time, and rebuilding replaces the image in the build folder.

### Copying to a real IIgs

The same build also creates `build/iigs/force-800k.2mg` and `build/iigs/force-800k.po`. These are two versions of the same 800K transfer disk. Use whichever format your disk-image mounting tool accepts.

Copy the whole image to your AFP share, then mount it on the IIgs. Using Finder on the IIgs, copy `FORCE` to your game disk and `Icons/FORCE.ICON` to that disk's `Icons` folder. The image keeps the IIgs file types intact, even if the transfer loses the image file's own type information. All missions and graphics are built into `FORCE`; there are no other game data files to copy.

The 800K disk is not bootable. Boot your normal GS/OS system first, mount the image, then launch or copy the game. Campaign progress is saved as `FORCE.STATE` in the game's launch directory, so use a writable destination.

### How the C64 and IIgs versions stay together

The C64 is the lead version. Each IIgs build reads the current C64 assembly and uses a Python script to turn its assembler syntax into ORCA/M source. ORCA/M then assembles that source into native IIgs code. The game does not run Python or interpret C64 code while you play.

Most game rules are shared this way: movement, combat, formations, cover, commands, reinforcements and bridge building. The maps and mission scripts are shared too. A gameplay fix in the C64 version will usually reach the IIgs in the next build, without having to make the same change twice.

The IIgs has its own input, graphics, loading, saves, title/menu and timing code. Changes in those parts need separate work. New C64 assembler features or hardware-specific code may also need changes to the conversion script. A successful build still needs testing on both machines.

The current IIgs version has no audio. Busy scenes can also run below its target of 20 game updates per second on a stock IIgs. Better IIgs artwork and more animation can be added later without changing the missions.

## Project documentation

- [User manual](MANUAL.md): how to play the current game.
- [Agent instructions](agents/README.md): source layout and implementation notes.
- [Build checks](agents/testing.md): verification instructions.
- [Game design](doc/README.md): intended rules, including features not yet implemented.
- [Code designs](design/README.md): proposed implementation changes.
