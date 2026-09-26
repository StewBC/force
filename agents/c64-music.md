# C64 title music

This feature is **C64-only**. The SDL build has no audio playback yet. This
note describes the composition and data model so a later SDL implementation
can adapt the musical intent without copying SID register behavior.

## Runtime contract

`src/c64/music.asm` is a three-voice SID player and the title score. The
whole of it — code, frequency tables, playback state, and score — occupies
`$0900–$0E9C` in the packed-map workspace and is deliberately transient.

`show_title` finishes drawing before calling `music_start`. The music player:

- installs a private VIC raster IRQ at line 250;
- advances the score at ten ticks per second;
- uses `$02A6` to choose a five-frame PAL or six-frame NTSC tick, and the
  matching frequency table;
- leaves the CIA key matrix to the title's foreground polling loop;
- begins a 45-frame volume fade after any key press;
- keeps the title visible during the fade;
- disables the raster source, clears all 25 SID registers, and returns with
  IRQs masked before `irq_init` installs the gameplay raster handler.

The fade is about 0.9 seconds on PAL and 0.75 seconds on NTSC. It is deliberately
quick: it removes the audiovisual cut without making dismissal feel sluggish.

Nothing here survives `map_load`. A later gameplay cue has to bring its own
player, or copy this one back into resident storage first. Do not play across
`map_load`.

## Composition

A slow lament in A minor, one pass of about 43 seconds, then all three voices
loop together. The picture is a man on a boat: wet, uncomfortable, and alone.
It does not lift.

1. Triangle bass. A low A pedal that drifts a few cents, so the hull never sits
   still. It rises a half step and slides back for the roll of the boat, and
   once falls from Eb into the pedal. Not a march.
2. Triangle line, in a low register. Short phrases that fall. F3 is as high as
   it goes, and that note sinks. Rests are him looking and not singing. No
   major chord.
3. Low-passed noise, resonance off, routed only while that voice is the sea.
   It is the water and the distant war. Three concussions swell in and fade;
   they are never struck. A square wave is not used.

Score ticks are a tenth of a second. `0` is a rest and `$FF` loops that voice.
`$F0` sets the instrument, `$F1` the filter center, `$F2` glides the next note.
Note `1` is C1. Glide, drift, and the filter move every frame; the score itself
stays at ten hertz. Both PAL and NTSC have a frequency table.

For an SDL adaptation, keep the slow minor line, the long rests, the dull
noise bed under it, and the same start-and-fade. A direct SID emulation is not
required. Start the audio only after the title is visible, fade it on any
dismissing key, and remove the title only after that short fade completes.
