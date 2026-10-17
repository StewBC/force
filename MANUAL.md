# FORCE user manual

FORCE is a single-player real-time strategy game. You command groups of soldiers with the keyboard. Your soldiers are blue; the enemy is red. The game keeps running while you enter commands.

## Starting the game

### Desktop

From the repository folder, run:

```sh
./build/src/sdl/force
```

If you have not built the game, follow the [build instructions](README.md#build-and-run).

### Commodore 64

Mount `build/force.d64` as drive 8, then enter:

```text
LOAD "FORCE",8,1
RUN
```

If you use an emulator with a folder mounted as drive 8, mount `build/c64` and autorun `build/force.prg`. The program needs the data files in that folder to load missions.

## Missions and progress

Press a key at the title screen. Use Up and Down to select a mission, then press RETURN to start.

Only the first mission is available at the start. Winning it opens the next. You can replay completed missions. The menu shows your best survivor count for each completed mission.

Each mission has its own objectives and enemy attacks. Short instructions appear below the map as the mission progresses. `SUCCESS` means you won; `DEFEAT` means you lost. Press RETURN after either result to return to the menu. A win saves your progress. A loss leaves your progress unchanged. F3 restarts the current mission immediately.

Wait for `SAVING` to finish before closing the game. If you see `SAVE FAILED`, progress has not been saved to disk. The desktop game stores progress in `build/c64/campaign.prg`; the C64 stores it in `CAMPAIGN` on drive 8.

## Keys

During keyboard play, hold **SHIFT for every command letter**, including section letters. For example, `MA` means SHIFT+M, then SHIFT+A. Release each letter before pressing the next. Numbers, punctuation, SPACE and RETURN do not need SHIFT.

| Key | Action |
| --- | --- |
| WASD or cursor keys | Move the map cursor. |
| M | Move quickly to a destination. |
| A | Advance to cover and fire. |
| D | Take cover at a destination and fire. |
| R | Withdraw while facing back toward the enemy. |
| H | Halt and keep firing. |
| K | Concentrate fire on one map square. |
| B | Build a bridge. |
| S | Transfer soldiers to another section. |
| J | Join two sections. |
| F | Centre the view on a location. |
| G | Return to the previous view. |
| C or X | Cycle through areas with recent fighting. |
| E | Cycle through recorded enemy positions. |
| A–H after a command | Choose a section. |
| . after a command | Choose the friendly soldier under the cursor. |
| 0–9 | Enter coordinates, a force value or a soldier count. |
| Comma or SPACE | Separate coordinates and the force value. |
| SPACE after C, X or E | View the selected area. |
| RETURN | Issue the command, using defaults for omitted details. |
| DEL or BACKSPACE | Delete a digit or go back to the previous command detail. |
| Esc | Cancel the command you are entering. |
| F3 | Restart the current mission. |
| F11 | Toggle fullscreen on the desktop. |

On the menu:

| Key | Action |
| --- | --- |
| Up / Down | Select a mission. |
| RETURN | Start the selected mission. |
| + | Show one more mission without completing the previous one. |
| - or * | Hide missions revealed with +. |
| F8, then F8 again | Erase campaign progress. Any other key cancels. |

Revealing missions with `+` lasts only for the current session.

A joystick or gamepad can move the cursor. After its first movement, command letters work without SHIFT and WASD becomes command input. On the desktop, unplugging the controller restores WASD movement. The fire button starts a selected mission on the menu; it has no action during play.

On the C64, use a joystick in port 2. RUN/STOP or the left-arrow key cancels a command. Use DEL to edit. The C64 cursor keys use SHIFT for Left and Up as usual. F11 is a desktop key only.

Close the desktop window to quit. Esc only cancels commands.

## Entering commands

Your soldiers belong to sections named A through H. The letters below the map show which sections have soldiers: white means occupied, grey means empty, and yellow marks the section you are choosing.

Most commands take these details, in order:

```text
Command  Section  Destination  Force
```

The screen labels these `VERB WHO WHERE FORCE`. Yellow shows which detail the game expects next. The line below shows the command you are entering. `CURSOR` shows the cursor's map coordinates.

Press RETURN whenever you have entered enough. The game fills in missing details:

- Section: the friendly section under the cursor, or the last section used.
- Destination: the cursor's current position.
- Force: 10.

Coordinates are `X,Y`, starting at `0,0` in the top-left corner of the map. X increases to the right; Y increases downward. You can still move the cursor while entering a command. On larger maps, moving it past the screen edge scrolls the view.

In these examples, type the characters inside the backticks, then press RETURN. Hold SHIFT for letters. There are no spaces between the command and section letters.

| Type | Result |
| --- | --- |
| `D` | Defend at the cursor with the default section. |
| `DA` | Section A defends at the cursor. |
| `MA4,18` | Section A moves to 4,18. |
| `DA4,18,5` | Section A defends at 4,18 with force 5. |
| `HA` | Section A halts. |
| `KA12,8` | Section A concentrates fire on 12,8. |

To set a force value, enter the coordinates, another comma or SPACE, then the value **before** RETURN. Once issued, a command stays in effect until it finishes, casualties cause a halt, or you replace it.

## Commands in detail

### Moving, attacking and defending

`M` moves soldiers faster than `A`, `D` or `R`. They do not fire while moving, but start firing when they arrive. They spread out around the destination. A soldier arriving at an available cover position can use it.

`A` and `D` send soldiers to cover in the destination area. Both currently let soldiers fire on the way and after arrival. Soldiers without a cover position spread out near the destination. Use these commands when you want soldiers to fight as they advance or take up defensive positions.

`R` also sends soldiers to cover, but they face opposite their direction of travel. Choose the withdrawal destination yourself.

`H` stops movement without moving soldiers out of their current positions. They continue firing.

Use `M` when speed matters. Use `D` when you want the section to occupy cover. Moving soldiers take less rifle damage than soldiers standing in the open; cover can protect them more, especially when it faces the incoming fire.

### Concentrating fire

`K` keeps soldiers in place and directs most of their rifle shots at the specified square. If no enemy is there or the target is out of range, they fire at other enemies normally. It does not make soldiers move closer or follow a moving target.

### Force values

Force controls how many casualties a section will accept before halting. A halt stops movement; the survivors still fire.

| Force | When the section halts |
| --- | --- |
| 0–3 | After the first death. |
| 4–6 | When half or fewer of the original soldiers remain. |
| 7–9 | When only one soldier remains. |
| 10 | Casualties do not cause a halt. |

The game counts from the section's strength when you issue the command. A new command starts the count again. Force 10 is the default.

### Ordering one soldier

Put the cursor on a friendly soldier, enter a command, then press `.` instead of a section letter. Move the cursor to the destination and press RETURN, or type coordinates.

For example, enter `M.`, move the cursor to a new position, then press RETURN. Only that soldier moves. The soldier stays in the same section. A later command to the whole section replaces this individual order.

Use `D.` to place one soldier in a particular cover position. `H.` halts one soldier, and `K.` directs that soldier's fire.

### Splitting and joining sections

With the cursor on a friendly soldier, `SB` transfers that soldier to section B. To transfer several soldiers, name the source section, destination section and count: `SAB2` transfers two soldiers from A to B. For `S`, the final number is a soldier count, not a force value. Give the receiving section an order afterward. A section using `K` cannot be split until you give it another command.

`JBA` joins B into A. Those soldiers become part of A and follow A's current order.

### Building bridges

Put the cursor on an unfinished bridge square and enter `BA`, then RETURN, to send section A to build it. You can also enter coordinates, such as `BA32,2`.

Soldiers work from beside unfinished bridge squares and advance as the bridge is completed. Several soldiers can build together. You cannot cross unfinished squares. The command only works at bridge construction sites supplied by the mission.

### Changing the view

`F` followed by RETURN centres the view on the cursor. `F30,10` centres it on those coordinates. `G` returns to the previous view. These are useful on maps larger than the screen.

`C` or `X` selects an area with recent fighting. Repeated presses select the next area. `E` does the same for recorded enemy positions. Press SPACE to view the selected area. A recorded position may no longer contain an enemy.

## Fighting

Soldiers choose targets and fire automatically. Their normal rifle target is the closest enemy within nine map squares. Rifle damage is lower from five squares away. In the current game, walls do not block ordinary rifle shots.

Buildings provide strong cover. Other cover protects soldiers mainly from the direction it faces. Soldiers can throw grenades automatically at nearby enemies in cover if they have grenades left.

Some missions include fixed gun nests and bazooka crews. Gun nests fire in a fixed direction and resist rifle fire. Bazooka crews carry four rockets and prefer gun nests as targets. After running out of rockets, or when no suitable nest is in range, they use rifles.

## DEVELOPER

### Files and tools

Use Tiled to edit maps. Open `assets/maps/force.tiled-project`, then open the mission's `.tmx` file. All maps use `assets/maps/tiles.tsx`, which refers to `assets/png/tiles.png`.

A mission uses three files:

| File | Purpose |
| --- | --- |
| `assets/maps/<name>.tmx` | Terrain, rooms, cover and starting soldiers. |
| `assets/scripts/<name>.txt` | Reinforcements, orders, objectives and win/loss conditions. |
| `assets/missions.txt` | Campaign order, map names and menu titles. |

The map and script must have the same name before the extension. For example, `farm.tmx` uses `farm.txt`. Tile classes are defined in `assets/tiles.txt`. Cover and other map markers are defined in `assets/properties.txt`.

### Tiled layers

Use an orthogonal map with 8×8 tiles and CSV layer data. Keep these layer names exactly as shown. Their order and visibility in Tiled do not change their meaning.

| Layer | What to put on it |
| --- | --- |
| `color` | Ground colours: grass, road, water and so on. |
| `tiles` | Visible scenery, including walls, roofs and barriers. |
| `rooms` | Rectangular areas used for movement and cover selection. |
| `properties` | Cover positions, doors, bridge construction sites and other markers. |
| `actors` | Starting soldier positions. |

Walls and barriers block movement. Roofs can be occupied by soldiers and are drawn over them. Blue ground, tile 118 on `color`, is water and blocks movement unless a bridge has been completed there.

Paint each room with one colour from the room markers. Each colour must form one filled rectangle. Two separate areas cannot share a colour. Every starting soldier and property marker must be inside a room. A room can touch another room along an edge. Open passages between them are found during the build. For a door through a wall, place a `portal` marker on `properties`.

Use `actors` for soldiers, rather than drawing soldiers on `tiles`. Each stamp places one soldier. Player stamps start in section A. In scripted missions, enemy stamps are ignored; use `spawn` in the script for enemies. The `actors` layer must exist even if it is empty.

The tileset has 160 tiles. Tiles 0–127 are game graphics. Tiles 128–159 are editor markers for `rooms` and `properties`; they do not appear in the game. Tiled's erase tool leaves an empty square. Tile 0 is a soldier tile, so painting it is not the same as erasing.

Do not flip or rotate tiles. Keep maps within 80×50 tiles and 4,000 tiles total. Room layouts should let soldiers walk fairly directly between entrances and destinations; divide complicated routes into separate rooms.

### Cover and bridges

Scenery and cover are separate. Drawing a wall or roof does not create a cover position. Place the matching marker on `properties` as well.

| Marker family | Meaning |
| --- | --- |
| `cover_hard_n/e/s/w` | Strong cover with a fixed facing direction. |
| `cover_soft_n/e/s/w` | Cover either side can use; facing follows the section's movement. |
| `cover_good_n/e/s/w` | Cover available when the section's rear faces the named direction. |
| `portal` | A passage through a wall. |
| `deck` | An unfinished bridge square. |

For example, `cover_hard_w` always faces west. `cover_good_w` is for a section with its rear to the west, facing east. Within one room, cover directions must all use the east–west axis or all use the north–south axis.

A room allows 24 cover positions, with at most 12 available to a section approaching from one direction. There can be 128 cover positions across the map. Use the marker names and bindings in `assets/properties.txt` to choose the correct tiles.

For a bridge, paint `deck` markers on `properties` and add `build deck 40` to the script header. This sets the work needed for each bridge square to 40 logic ticks for one soldier. More soldiers can help. Tile 80 is the unfinished bridge; tile 81 is the completed bridge.

Objective, mine and scout markers also exist in the file format. A marker alone does not define a mission's win condition. Write that condition in the script. Mine gameplay is not implemented.

### Registering a mission

Add a line to `assets/missions.txt`:

```text
normandy farm "Hold the Farm"
```

The first value groups maps that share a setting into C64 data files. The second names the map and script. The quoted text is the menu title. File order is campaign order. An optional `cam=x,y` before the title sets the starting camera position. The whole map is playable.

Names can contain letters, digits and underscores and must start with a letter or underscore. Map names and setting names are limited to 15 characters. Titles are limited to 27 characters. The C64 build allows 16 missions and four settings.

### Mission scripts

Scripts control the sequence of events. Soldiers still move, choose cover and fight through the game's normal rules.

A script can contain:

- Header settings: room names, default spawn room, grenade supplies and bridge work.
- `init:`: actions performed once when the mission loads.
- `watch`: a condition checked throughout the mission, such as losing all friendly soldiers.
- `beat <name>:`: a named stage containing actions and a wait for the next stage.

Keywords such as `spawn` and `wait` are lowercase. Order letters and section letters are uppercase. `#` starts a comment outside quoted text.

Use explicit names such as `enemy.A` and `player.B` for sections. A bare `A` means `enemy.A` in a script. `player.strength` means the total surviving friendly soldiers.

This example uses rooms from the farm map. It sends an enemy section toward the houses, then wins when that section is gone and a friendly soldier has reached the field:

```text
room houses = colour 1
room field = colour 4
spawn_room field

player_grenades 8
player_grenade_wait 50

watch wipe: player.strength == 0 -> lose

init:
  objective "Defend, then advance west"

beat attack:
  spawn 6 enemy.A in spawn_room batch 2 period 7
  order enemy.A A room houses force 10
  wait job idle -> fighting

beat fighting:
  wait enemy.A.strength == 0 and player.in field >= 1 -> finished

beat finished:
  win
```

The room aliases refer to the colours painted on `rooms`, not their order in the map file. `spawn` adds six enemies, two at a time, seven logic ticks apart. The following `order` runs without waiting for every soldier to arrive. `wait job idle` waits for the whole group to spawn. Only then does the next stage check whether they have all been defeated.

A logic tick is one game update, every three display frames. Script periods and grenade waits use these ticks, not seconds.

`wait` pauses the script sequence until its condition is true, then jumps to the named stage. Its condition is first checked on a later tick. A wait can combine two conditions with `and`. A watch is checked while the sequence is waiting too. Use watches for conditions that must apply throughout the mission.

### Script commands

| Command | Example | Meaning |
| --- | --- | --- |
| `spawn` | `spawn 4 player.B in field` | Add soldiers to a section in a room. |
| `spawn ... at` | `spawn 1 enemy.C at 22,5 kind nest facing e` | Place a unit at an exact map position. |
| `order` | `order enemy.A D room houses force 5` | Give a section an order. |
| `objective` | `objective "Clear the road"` | Display a short instruction. |
| `wait` | `wait bridge built -> relief` | Wait for a condition, then change stage. |
| `goto` | `goto attack` | Change stage immediately. |
| `set spawn_room` | `set spawn_room field` | Change the default room for later spawns. |
| `approach` | `approach houses W` | Set the approach direction used for cover selection. |
| `win` / `lose` | `win` | End the mission. |

Script orders support `A`, `D`, `M`, `H` and `R`. The `force` value is required. Destinations can be `room <name>`, `cell x,y`, or an exit such as `exit-west`. An enemy ordered to `M` toward an exit leaves the map. Use explicit rooms or coordinates for orders shared with the C64; its script handling does not support the `player` destination.

Spawns default to infantry. Use `kind bazooka` for a bazooka crew or `kind nest facing n/e/s/w` for a fixed gun nest. Nests need an exact position. Exact-position spawns wait for that square to become free. Use `batch` and `period` to stagger arrivals. An exact-position spawn in `init:` must contain only one unit.

Conditions include section strength, soldiers in a room, arrival at a square, elapsed ticks, and bridge completion. For example:

| Condition | Meaning |
| --- | --- |
| `enemy.A.strength <= 2` | Section A has at most two enemies left. |
| `player.in field >= 1` | At least one friendly soldier is in the field. |
| `enemy.A at 12,8` | A soldier from enemy A is at 12,8. |
| `clock >= 100` | At least 100 logic ticks have passed since mission load. |
| `job idle` | All soldiers from the pending spawn have arrived. |
| `bridge built` | Every bridge square on the map is complete. |

A watch can end the mission, change the spawn room or approach direction, or jump to a stage. It cannot spawn soldiers, issue orders or use `job idle`. Use a stage for those actions. Non-ending watch actions run once; you can add `once` explicitly.

### Building and checking content

Run the [build commands](README.md#build-and-run) after saving maps or scripts. The desktop build uses `tools/gen_sdl.py` to check the content and generate C data. The C64 build uses `tools/gen_c64.py` and `tools/c64_package.py` to generate and package the same content. The game does not read TMX or script text during play. Do not edit generated files.

For a new C64 mission, also add its map and script to the dependency and generation lists in `src/c64/CMakeLists.txt`. If you add a setting, update its container output and disk packaging lists there too. Rebuild the program and data files together, then recreate the disk image if you use one.

The build reports invalid layers, room shapes, markers and script syntax. Scripts allow 64 actions, 12 stages, eight watches, 32 conditions, 16 distinct destinations and eight spawn definitions. Script names are limited to 15 characters. Objective messages are limited to 38 characters.

Run `./build/src/sdl/force --smoke` for the basic game checks, then play the mission. Check that all waves arrive, soldiers can reach their destinations, bridges can be completed, and both victory and defeat work. A successful build does not prove the mission can be won.

See [asset implementation notes](agents/assets.md) for format details and [verification instructions](agents/testing.md) for the C64 checks. The existing scripts in `assets/scripts/` provide more examples.
