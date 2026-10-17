"""Strict build-time adapter for the lead C64 simulation and cell compositor.

Only syntax is translated. Hardware routines are explicit IIgs replacements.
The output executes native 65816 instructions with M=X=1, not emulation mode.
"""
from pathlib import Path
import re

MODULES = ('map', 'game', 'command', 'world', 'move', 'combat', 'draw', 'deck', 'tactics')
OMIT = {'game_tick', 'place_cursor', 'deck_geo_size', 'deck_geo_copy',
        'install_routes', 'initial_routes', 'activate_routes', 'patch_variant'}
BRANCHES = {'bcc':'bcs', 'bcs':'bcc', 'beq':'bne', 'bne':'beq',
            'bmi':'bpl', 'bpl':'bmi', 'bvc':'bvs', 'bvs':'bvc'}

CONSTANTS = {}

def expression(s):
    s = re.sub(r"'([^'])'", lambda m:str(ord(m[1])), s)
    s = re.sub(r'\b([A-Za-z_]\w*)::([A-Za-z_]\w*)', r'\1__\2', s)
    # ORCA evaluates expressions left to right. Parenthesize shifted operands.
    # Fold numeric/constant expressions, including C64 bitwise operators.
    prefix = '#' if s.startswith('#') else ''
    expr = s[len(prefix):]
    expr = re.sub(r'\$([0-9A-Fa-f]+)', r'0x\1', expr)
    expr = re.sub(r'\b[A-Za-z_]\w*\b', lambda m: str(CONSTANTS.get(m[0], m[0])), expr)
    if re.fullmatch(r'[0-9a-fA-Fx()+*/|^&% \-]+', expr):
        try: return prefix+str(int(eval(expr, {'__builtins__': {}}, {})))
        except (ValueError, TypeError, SyntaxError, NameError): pass
    return s.replace(' ', '')

def translate(text, origin, omit=OMIT, expand=frozenset()):
    lines = text.splitlines()
    scopes = {}
    proc = None
    for line in lines:
        s=line.split(';',1)[0].strip()
        if s.startswith('.proc '): proc=s.split()[1]; scopes[proc]=[]
        elif s=='.endproc': proc=None
        elif proc:
            m=re.match(r'(\w+):',s)
            if m: scopes[proc].append(m[1])
    result=[]; proc=None; branch=0
    for lineno,line in enumerate(lines,1):
        code,_,comment=line.partition(';'); s=code.strip()
        if s.startswith('.proc '):
            proc=s.split()[1]
            if proc not in omit: result += [f'; {origin}:{lineno}', f'{proc} anop']
            continue
        if s=='.endproc': proc=None; continue
        if proc in omit or not s: continue
        if s.startswith('.segment'): continue
        if s.startswith('.include'): raise ValueError(f'{origin}:{lineno}: unexpected include')
        if proc:
            for local in sorted(scopes[proc],key=len,reverse=True):
                s=re.sub(r'(?<![\w:])'+re.escape(local)+r'\b', proc+'__'+local, s)
        label=''
        m=re.match(r'(\w+):\s*(.*)',s)
        if m: label,s=m.groups()
        m=re.match(r'(\w+)\s*=\s*(.*)',s)
        if m:
            name,value=m.groups(); value=expression(value)
            if value.isdigit(): CONSTANTS[name]=int(value)
            result.append(f'{name} equ {value}'); continue
        if s.startswith('.res '):
            count=s[5:].split(',')[0].strip(); result.append(f'{label} ds {expression(count)}'); continue
        if s.startswith('.byte '):
            tokens=re.findall(r'"[^"]*"|[^,]+',s[6:]); values=[]
            for token in tokens:
                token=token.strip()
                if token.startswith('"'): values.extend(str(v) for v in token[1:-1].encode('ascii'))
                else:
                    token=re.sub(r'^>(\w+)$',r'\1|-8',token)
                    token=re.sub(r'^<(\w+)$',r'\1',token)
                    values.append(expression(token))
            result.append(f'{label} dc i1\'{",".join(values)}\''); continue
        if s.startswith('.word '): result.append(f'{label} dc i2\'{expression(s[6:])}\''); continue
        if s.startswith('.'): raise ValueError(f'{origin}:{lineno}: unsupported {s}')
        if not s: result.append(f'{label} anop'); continue
        op,_,operand=s.partition(' '); op=op.lower(); operand=operand.strip()
        if op in ('sei','cli'):
            # No C64 IRQ owns any state; leave interrupt mask to the platform.
            result.append(f'{label} nop'); continue
        if op not in {'adc','and','asl','bit','clc','cld','cmp','cpx','cpy','dec','dex','dey','eor','inc','inx','iny','jmp','jsr','lda','ldx','ldy','lsr','nop','ora','pha','php','pla','plp','rol','ror','rts','sbc','sec','sta','stx','sty','tax','tay','tsx','txa','txs','tya',*BRANCHES}:
            raise ValueError(f'{origin}:{lineno}: unknown instruction {op}')
        if op in ('asl','lsr','rol','ror') and not operand: operand='a'
        if op in BRANCHES:
            key=f'{origin}:{lineno}'
            if key in expand:
                branch+=1; skip=f'longbranch_{origin}_{branch}'
                result += [f'{label} {BRANCHES[op]} {skip}',f' jmp {operand}',f'{skip} anop']; continue
        if s=='adc #$D4': operand='#>(COLORRAM-SCREEN)'
        if operand=='$02A6': operand='ntsc_flag'
        if operand=='$BF00,x': operand='route_components,x'
        result.append(f'{label} {op} {expression(operand)}'.rstrip())
    return '\n'.join(result)+'\n'

def generate(root, out, expand=frozenset()):
    chunks=[]
    equ=(root/'src/c64/equ.inc').read_text()
    # Platform-owned storage gets relocatable labels, never C64 physical homes.
    equ=equ.split('; Always-RAM flags.')[0]
    equ='\n'.join(line for line in equ.splitlines() if not line.startswith('.include'))
    chunks.append(translate(equ,'equ',omit=set()))
    zp=(root/'src/c64/zp.asm').read_text()
    offset=0
    for name,n in re.findall(r'(\w+):\s*\.res\s+(\d+)',zp):
        chunks.append(f'{name} equ ${offset:02X}\n'); offset+=int(n)
    (out/'contracts.s').write_text('\n'.join(chunks))
    chunks=[]
    for name in MODULES:
        chunks.append(translate((root/f'src/c64/{name}.asm').read_text(),name,expand=expand))
    chunks.append(translate((root/'src/c64/bss.asm').read_text(),'bss',omit=set()))
    includes=[]
    for i,chunk in enumerate(chunks):
        name=f'core{i}.s'
        (out/name).write_text(chunk)
        includes.append(f' copy build/iigs/{name}')
    (out/'core.s').write_text('\n'.join(includes)+'\n')
