"""Fixed aligned 8x8 stack compiler; no arbitrary-size sprite optimizer.

Compile each opaque C64 multicolour glyph once. Its paper pixels are runtime
masked; this avoids producing a separate routine for every background colour.
Units, text and effects continue through the composed-cell stack fallback.
"""
from pathlib import Path
from collections import Counter


def words(glyph):
    """Return (constant, paper-mask) words in stack push order."""
    for row in reversed(glyph):
        pairs=[(row>>shift)&3 for shift in (6,4,2,0)]
        pixels=[(0x22,0xBB,0xEE,0)[p] for p in pairs]
        mask=[255 if p==3 else 0 for p in pairs]
        for index in (2,0):
            yield pixels[index]|pixels[index+1]<<8,mask[index]|mask[index+1]<<8


def compile_sprites(charset, output):
    lines=[' case on',' ALIGN 256','TILESPR START TILESPR','draw_tile ENTRY',
           '; ABI native16: A=paper repeated in all nibbles, X=glyph*2,',
           '; Y=bank-$01 screen top-left; preserves P/DBR/D/S, trashes A/X/Y.',
           ' php',' sei',' rep #$30',' longa on',' longi on',' phb',' phd',
           ' sta >sprite_paper',' tsc',' sta >sprite_saved_stack',
           ' sep #$20',' longa off',' lda >$E0C068',' sta >sprite_saved_state',
           ' ora #$30',' sta >$E0C068',' rep #$20',' longa on',' tya',' clc',
           ' adc #1123',' tcs',' jmp (sprite_vectors,x)',
           'sprite_restore anop',' lda >sprite_saved_stack',' tcs',
           ' sep #$20',' longa off',' lda >sprite_saved_state',' sta >$E0C068',
           ' rep #$20',' longa on',' pld',' plb',' plp',' rtl',
           'sprite_vectors anop',
           *[" dc a2'"+','.join('tile_'+str(i) for i in range(j,j+16))+"'" for j in range(0,128,16)],
           'sprite_paper ds 2','sprite_saved_stack ds 2','sprite_saved_state ds 1']
    for tile in range(128):
        lines += [f'tile_{tile} anop']
        data=list(words(charset[tile*8:tile*8+8]))
        # Two fixed pattern registers survive row-to-row stack address changes.
        # This is deliberately limited to aligned 8x8 cells, not a general sprite
        # optimizer. Paper-only ground becomes one load and sixteen PHX pushes.
        def benefit(pattern):
            base,mask=pattern
            if not mask: return data.count(pattern)-3
            load=5+(3 if mask!=65535 else 0)+(3 if base else 0)
            return data.count(pattern)*load-(load+2)
        cached=[p for p in sorted(Counter(data),key=benefit,reverse=True) if benefit(p)>0][:2]
        registers={pattern:reg for pattern,reg in zip(cached,('x','y'))}
        for (base,mask),reg in registers.items():
            if not mask:
                lines += [f' ld{reg} #${base:04X}']
            else:
                lines += [' lda >sprite_paper']
                if mask!=65535: lines += [f' and #${mask:04X}']
                if base: lines += [f' ora #${base:04X}']
                lines += [' ta'+reg]
        for i,(base,mask) in enumerate(data):
            if (base,mask) in registers:
                lines += [' ph'+registers[(base,mask)]]
            elif mask==0:
                lines += [f' pea ${base:04X}']
            else:
                lines += [' lda >sprite_paper']
                if mask!=65535: lines += [f' and #${mask:04X}']
                if base: lines += [f' ora #${base:04X}']
                lines += [' pha']
            if i%2==1 and i<15: lines += [' tsc',' sec',' sbc #156',' tcs']
        lines += [' jmp sprite_restore']
    lines += [' END']
    output.write_text('\n'.join(lines)+'\n')
