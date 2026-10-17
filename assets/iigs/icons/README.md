# FORCE Finder icon

A small pineapple grenade, with separate normal and small versions. The `.txt`
files are the editable artwork: a hex digit is a colour, and `.` is transparent.
Black (`0`) is still an opaque colour. Each source pixel is doubled horizontally
for the Finder's narrow 640-mode pixels.

The normal source is 24×24 and the small source is 12×12. Run the normal IIgs
build, or `python3 tools/iigs/icons.py`, to make `build/iigs/icons/FORCE.ICON` and
its previews. Generated files stay in the build folder.

The build puts the icon in the disk's `Icons` folder as type `$CA`, aux `$0000`.
It matches the application named `FORCE`, type `$B3`, aux `$DB03`. Copy the icon
with those attributes if installing the game on another disk. The filename/type
association follows Time Pilot's setup and Apple's [Finder icon file type note](https://mirrors.apple2.org.za/Apple%20II%20Documentation%20Project/Software/Operating%20Systems/Apple%20ProDOS/Documentation/Apple%20ProDOS%20File%20Type%20Notes.pdf#page=145).
