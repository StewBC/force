# C64 title music

This feature is **C64-only**. The SDL build has no audio playback yet. This
note describes the composition and data model so a later SDL implementation
can adapt the musical intent without copying SID register behavior.

## Runtime contract

`src/c64/music.asm` is a three-voice SID player and the title score. The
player, frequency tables, playback state, and score are resident `CODE`.
`$0900` belongs to the packed mission, so the menu can return to a map
that is already loaded without discarding the song.

`show_title` finishes drawing before calling `music_start`. The player:

- installs a private VIC raster IRQ at line 250;
- advances the score at ten ticks per second;
- uses `$02A6` to choose a five-frame PAL or six-frame NTSC tick, and the
  matching frequency table;
- leaves the CIA key matrix to the title and menu polling loops;
- keeps playing when RETURN leaves the picture for the menu;
- fades across 45 frames when a mission is chosen, then `music_stop` clears
  all 25 SID registers and drops the raster source.

The menu calls `music_start` only when `music_on` is clear, which is the
return from a mission. That start begins the piece again from the top.
The fade is about 0.9 seconds on PAL and 0.75 seconds on NTSC. Do not play
across `map_load`; the mission installs the battle raster handler after
`music_stop`.

## Composition

A slow lament in A minor. Each voice is 432 score ticks, 43.2 seconds, and
then loops with the others. The picture is a man on a boat: wet, uncomfortable,
and alone. It does not lift. A square wave is not used.

Times below are seconds from the start of the loop. The byte score in
`music.asm` is the same list; note `1` is C1, and a tick is a tenth of a second.

**Line** (triangle, a little under the bass). Attack about a tenth of a second,
then a slow settle, release about three quarters of a second. One shape, said
again: a low note, a leap, a step down, and home on A. The second leap is
only up to D. The third reaches F and stops on C instead of A. The boat-roll
starts that same shape on Bb and still ends on A. Then the first leap
returns, and the last phrase only climbs to C before the long A. F3 is as
high as he goes.

| From | Notes |
|------|--------|
| 0.0 | rest 2.4 |
| 2.4 | A2 0.6, E3 1.8, D3 0.6, C3 1.2, A2 2.4 |
| 9.0 | D3 1.8, C3 0.6, A2 3.6 |
| 15.0 | F3 1.8, E3 0.6, D3 1.2, C3 1.8 |
| 20.4 | Bb2 0.6, D3 1.8, C3 0.6, Bb2 1.2, A2 2.4 |
| 27.0 | E3 1.8, D3 0.6, C3 1.2, A2 2.4 |
| 33.0 | C3 1.8, Bb2 1.8, A2 6.6 |

**Bass** (triangle). Soft attack, strong sustain, short release. A low A drifts
a few cents over about two and a half seconds, so the hull never sits still.
Slides are legatos: the half step takes about a second, and the fall from Eb
arrives during its own note. A repeated A at the loop point does not
retrigger.

| From | What |
|------|------|
| 0.0 | A1 0.4, then a concussion (0.2) and a rest (1.0) while it fades |
| 1.6 | A1 8.0 |
| 9.6 | A1 5.4, D2 1.8, A1 2.4 |
| 19.2 | concussion 0.2, rest 1.4, slide up to Bb1 for 4.2, slide back to A1 for 3.8 |
| 28.8 | D2 2.8, concussion 0.2, rest 1.0, C2 1.0, Eb2 2.4, slide down to A1 for 2.2 |
| 38.4 | A1 4.8, held across the loop |

Keep these intervals. Do not "correct" them into a major chord:

- The opening line sits on A: fifth, fourth, minor third, a short major
  second, octave.
- Under the F3 phrase the bass stays on A through that F and the E after it.
  C under that E would be a major third. D arrives only under the following D.
- The boat-roll is the Bb. The line leaps from Bb to D (a minor third, not a
  major chord) and comes back to A as the bass slides home.
- Eb in the bass sits under C then Bb in the line. The line's A arrives once
  the bass has already left Eb. It does not resolve upward.

**Sea** (noise, not a tuned voice). Low-pass, no resonance. A resonant filter
turns this layer into a whistle and covers the line; that mix was rejected.
The bed decays in a fraction of a second to a sustain well under the line.
Gaps are the lonely bars. The noise "pitch" only chooses how coarse the hiss
is. A slow filter swell of several seconds breathes under it, and each
concussion opens the filter a step for less than a second, then it closes.
The concussion is the same noise with an attack aimed at a full second, but
the gate lasts only two tenths, so it never reaches a crack. It replaces the
bass note. It is not a drum on top.

| From | Sea |
|------|-----|
| 0.0 | low wash 6.0, gap 3.6 |
| 9.6 | gap 1.2, a little more open for 7.2, gap 1.2 |
| 19.2 | wash 2.4, gap 0.8, lower wash 4.8, gap 1.6 |
| 28.8 | wash 4.0, gap 0.8, darker wash 2.0, gap 2.8 |
| 38.4 | gap 2.0, low wash 2.8, held across the loop |

`$F0` sets the instrument, `$F1` the filter center, `$F2` glides the next
note, `0` rests, `$FF` loops that voice. Glide, drift, and the filter move
every frame; the score itself stays at ten hertz. Both PAL and NTSC have a
frequency table.

For an SDL adaptation, play this score with three monophonic voices: two
dull triangles and one quiet low-passed noise. Do not copy SID registers.
Start the audio only after the title is visible, fade it on any dismissing
key over the same short time (45 video frames: about 0.9 seconds on PAL,
0.75 on NTSC), and remove the title only after that fade completes.
