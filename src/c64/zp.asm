; Zero page. World procs may trash zPtr, zPtr2, zA0-zA4, zR0, zT0-zT7.
; Draw also uses zSrc and zDst. World must not touch zSrc or zDst.

zPtr:   .res 2
zPtr2:  .res 2
zSrc:   .res 2
zDst:   .res 2
zA0:    .res 1
zA1:    .res 1
zA2:    .res 1
zA3:    .res 1
zA4:    .res 1
zR0:    .res 1
zT0:    .res 1
zT1:    .res 1
zT2:    .res 1
zT3:    .res 1
zT4:    .res 1
zT5:    .res 1
zT6:    .res 1
zT7:    .res 1
