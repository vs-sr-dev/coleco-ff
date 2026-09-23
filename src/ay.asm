; ay.asm — AY-3-8910 register write helper per ColecoVision SGM.
;
; SGM espone AY-3-8910 sui port:
;   $50 = register select (write)
;   $51 = data            (write)
;
; Calling convention: __z88dk_fastcall, 1 int arg in HL.
;   H = register number (0-15)
;   L = data byte
; Caller packs con AY_PACK(reg,val) = (reg << 8) | val.

    SECTION code_user

    PUBLIC  _ay_write

; void ay_write(unsigned int reg_val) __z88dk_fastcall
_ay_write:
    ld      a, h
    out     ($50), a            ; register select
    ld      a, l
    out     ($51), a            ; data write
    ret
