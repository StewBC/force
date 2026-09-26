# C64 title music

This feature is **C64-only**. The SDL build has no audio playback yet. This
note describes the composition and data model so a later SDL implementation
can adapt the musical intent without copying SID register behavior.

## Runtime contract

`src/c64/music.asm` contains a small three-voice SID sequencer. Its executable
player is in resident `CODE`; the title-only score, frequency table, and nine
bytes of playback state occupy `$0900–$0A34`. That range is the packed-map
workspace and is deliberately transient.

`show_title` finishes drawing before calling `music_start`. The music player:

- installs a private VIC raster IRQ at line 250;
- advances the score at ten ticks per second;
- uses `$02A6` to choose a five-frame PAL or six-frame NTSC tick;
- leaves the CIA key matrix to the title's foreground polling loop;
- begins a 45-frame volume fade after any key press;
- keeps the title visible during the fade;
- disables the raster source, clears all 25 SID registers, and returns with
  IRQs masked before `irq_init` installs the gameplay raster handler.

The fade is about 0.9 seconds on PAL and 0.75 seconds on NTSC. It is deliberately
quick: it removes the audiovisual cut without making dismissal feel sluggish.

The resident code is suitable for future short cues, but the current frequency
table and playback state are title-transient. A gameplay cue should either
restore those small tables after `map_load` or move the common table/state into
resident storage when the first cue is added. Do not play across `map_load`.

## Composition: “Grey Horizon”

The title cue is an original slow lament in D minor. Its requested image is a
sea captain watching a troubled, slightly stormy horizon: tired resolve rather
than spectacle, with war felt as pressure rather than depicted as action.

The three voices have distinct jobs:

1. A triangle bass holds an inexorable D/A pedal and occasionally moves through
   C and F. The rests prevent it becoming a march.
2. A soft triangle melody rises in short phrases, but repeatedly falls away
   before reaching a comfortable resolution. Its slower attack and lower
   sustain keep it behind the strengthened bass rather than piercing the mix.
3. A low triangle counter-line answers like distant horns or the slow motion of
   the sea.

There are no sampled drums, bright pulse lead, or aggressive filter dependency.
That keeps the piece restrained and makes it less sensitive to differences
between SID models and emulators. Notes are stored as `(chromatic note, duration)` byte pairs;
`0` is a rest and `$FF` loops a voice. Durations are score ticks, nominally one
tenth of a second.

For an SDL adaptation, preserve the tempo, minor harmony, independent rests,
and restrained envelopes. A direct SID emulation is not required: three simple
monophonic triangle synth voices are enough. Start the audio
only after the title is visible, fade it on any dismissing key, and remove the
title only after that short fade completes.
