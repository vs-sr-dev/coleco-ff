;       ColecoVision SGM-enabled crt0 — custom per progetto ColecoFF.
;       Combina coleco_crt0.asm + rom.asm originali z88dk (target/coleco/classic)
;       con due modifiche:
;       1. SGM enable (OUT $53,$01) iniettato all'entry point `program:`
;          prima di qualsiasi setup di stack o BSS.
;       2. SP iniziale spostato da $7400 (top stock 1KB) a $7FFE (top SGM 24KB).
;       Tutto il resto del flusso z88dk e' identico al default startup=1.

    MODULE  coleco_sgm_crt0

    defc    crt0 = 1
    INCLUDE "zcc_opt.def"

    EXTERN  _main
    EXTERN  msxbios

    PUBLIC  l_dcal
    PUBLIC  __Exit
    defc    CONSOLE_COLUMNS = 32
IF !DEFINED_CONSOLE_ROWS
    defc    CONSOLE_ROWS = 24
ENDIF

    EXTERN    __vdp_enable_status
    EXTERN    VDP_STATUS
    EXTERN    __tms9918_status_register

    defc    __CPU_CLOCK = 3579545

    EXTERN    vdp_set_mode
    EXTERN    asm_im1_handler
    EXTERN    nmi_vectors
    EXTERN    asm_interrupt_handler

IF !DEFINED_CRT_ORG_BSS
    defc    CRT_ORG_BSS = 0x7000
ENDIF
    defc    CRT_ORG_CODE = 0x8000

    defc    TAR__fputc_cons_generic = 1
    defc    TAR__no_ansifont = 1
    defc    TAR__clib_exit_stack_size = 0
    defc    TAR__register_sp = 0x7FFE       ; <-- SGM: top of 24KB invece di 0x7400
    defc    TAR__crt_enable_eidi = $02
    defc    TAR__crt_on_exit = $0000
    defc    CRT_KEY_DEL = 127

IF !DEFINED_CLIB_FOPEN_MAX
    defc    DEFINED_CLIB_FOPEN_MAX = 1
    defc    CLIB_FOPEN_MAX = 3
ENDIF
    defc    DEFINED_basegraphics = 1
IFNDEF CLIB_DEFAULT_SCREEN_MODE
    defc    CLIB_DEFAULT_SCREEN_MODE = 2
ENDIF


    INCLUDE "crt/classic/crt_rules.inc"

    org     CRT_ORG_CODE

    defb    0x55, 0xaa            ;Title screen + 12 second delay (0xAA,0x55 per skip)
IF CRT_COLECO_SPRITE_NAME_SIZE > 0
   defw     _os7_sprite_order_table
ELSE
    defw    0
ENDIF
IF CRT_COLECO_SPRITE_ORDER_SIZE > 0
   defw     _os7_sprite_order_table
ELSE
    defw    0
ENDIF
IF CRT_COLECO_BIOS_BUFFER_SIZE > 0
   defw     _os7_bios_buffer
ELSE
    defw    0
ENDIF
IF CRT_COLECO_BIOS_CONTROLLER_SIZE > 0
   defw     _os7_bios_controller
ELSE
    defw    0
ENDIF
    defw    program                ;Where to start execution from
IF ((__crt_enable_rst & $0202) = $0002)
    EXTERN  _z80_rst_08h
    jp      _z80_rst_08h
ELSE
    jp        restart_ret
ENDIF
IF ((__crt_enable_rst & $0404) = $0004)
    EXTERN  _z80_rst_10h
    jp      _z80_rst_10h
ELSE
    jp        restart_ret
ENDIF
IF ((__crt_enable_rst & $0808) = $0008)
    EXTERN  _z80_rst_18h
    jp      _z80_rst_18h
ELSE
    jp        restart_ret
ENDIF
IF ((__crt_enable_rst & $1010) = $0010)
    EXTERN  _z80_rst_20h
    jp      _z80_rst_20h
ELSE
    jp        restart_ret
ENDIF
IF ((__crt_enable_rst & $2020) = $0020)
    EXTERN  _z80_rst_28h
    jp      _z80_rst_28h
ELSE
    jp        restart_ret
ENDIF
IF ((__crt_enable_rst & $4040) = $0040)
    EXTERN  _z80_rst_30h
    jp      _z80_rst_30h
ELSE
    jp        restart_ret
ENDIF
IF ((__crt_enable_rst & $8080) = $0080)
    EXTERN        _z80_rst_38h
    jp      _z80_rst_38h
ELSE
    jp        asm_im1_handler        ;Maskable interrupt
ENDIF
IF (__crt_enable_nmi > 1)
    EXTERN        _z80_nmi
    jp        _z80_nmi
ELSE
    jp        nmi_int                ;NMI
ENDIF
    defm        " / / "

restart_ret:
    ret

;; ============================================================
;; SGM init + standard z88dk init flow
;; ============================================================

program:
    ;; ---- SGM enable, before anything that touches RAM ----
    di                              ; mask Z80 maskable INT durante transizione

    ; Disable VBlank NMI + blank screen (R1 = 0x80)
    ; Necessario per evitare che la NMI BIOS giri durante lo swap RAM
    ld      a, 0x80
    out     (0xBF), a
    ld      a, 0x81                 ; reg 1 con high-bit (= register write)
    out     (0xBF), a

    ; Enable SGM: 24 KB RAM su $2000-$7FFF
    ld      a, 0x01
    out     (0x53), a

    ; Silenzia SN76489 (porta 0xFF, latch byte 1cc1vvvv, vvvv=F mute)
    ; Senza questo, su real HW / MAME il chip canta da power-on.
    ld      a, 0x9F                 ; ch0 mute
    out     (0xFF), a
    ld      a, 0xBF                 ; ch1 mute
    out     (0xFF), a
    ld      a, 0xDF                 ; ch2 mute
    out     (0xFF), a
    ld      a, 0xFF                 ; ch3 (noise) mute
    out     (0xFF), a

    ; Silenzia AY-3-8910 della SGM: mixer R7=0xFF (tutto off) + volumi R8/R9/R10=0
    ld      a, 0x07
    out     (0x50), a
    ld      a, 0xFF
    out     (0x51), a
    ld      a, 0x08
    out     (0x50), a
    xor     a                       ; A = 0
    out     (0x51), a
    ld      a, 0x09
    out     (0x50), a
    xor     a
    out     (0x51), a
    ld      a, 0x0A
    out     (0x50), a
    xor     a
    out     (0x51), a

    ; ---- Da qui prosegue il flusso z88dk standard ----
    ; crt_init_sp.inc setta SP a TAR__register_sp = 0x7FFE (top SGM RAM)
    INCLUDE "crt/classic/crt_init_sp.inc"
    call    crt0_init
    INCLUDE "crt/classic/crt_init_atexit.inc"
    INCLUDE "crt/classic/tms99x8/tms99x8_mode_init.inc"
    im      1

    INCLUDE "crt/classic/crt_init_heap.inc"
    INCLUDE "crt/classic/crt_init_eidi.inc"

    call     _main
__Exit:
    call    crt0_exit
    INCLUDE "crt/classic/tms99x8/tms99x8_mode_exit.inc"
    INCLUDE "crt/classic/crt_exit_eidi.inc"
    INCLUDE "crt/classic/crt_terminate.inc"



IF (__crt_enable_nmi <= 1)
nmi_int:
    push    af
    push    hl
    ld      a,(__vdp_enable_status)
    rlca
    jr      c,no_vbl
    in      a,(VDP_STATUS)
    ld      (__tms9918_status_register),a
no_vbl:
    ld      hl,nmi_vectors
    call    asm_interrupt_handler
    pop     hl
    pop     af
    retn
ENDIF


; Safe BIOS call
msxbios:
    push    ix
    ret


l_dcal:
    jp      (hl)            ;Used for function pointer calls

    ; Point the font to the ROM if not overriden
IFNDEF DEFINED_CRT_FONT
    PUBLIC CRT_FONT
    defc CRT_FONT = 5539
ENDIF


    INCLUDE "crt/classic/crt_runtime_selection.inc"

    defc        __crt_org_bss = CRT_ORG_BSS
    IF DEFINED_CRT_MODEL
        defc __crt_model = CRT_MODEL
    ELSE
        defc __crt_model = 1
    ENDIF
    INCLUDE        "crt/classic/crt_section.inc"


    SECTION bss_crt

IF CRT_COLECO_SPRITE_NAME_SIZE > 0
    PUBLIC  _os7_sprite_name_table
_os7_sprite_name_table:
    defs    CRT_COLECO_SPRITE_NAME_SIZE
ENDIF
IF CRT_COLECO_SPRITE_ORDER_SIZE > 0
   PUBLIC _os7_sprite_order_table
_os7_sprite_order_table:
   defs     CRT_COLECO_SPRITE_ORDER_SIZE
ENDIF
IF CRT_COLECO_BIOS_BUFFER_SIZE > 0
   PUBLIC _os7_bios_buffer
_os7_bios_buffer:
   defs    CRT_COLECO_BIOS_BUFFER_SIZE
ENDIF
IF CRT_COLECO_BIOS_CONTROLLER_SIZE > 0
   PUBLIC  _os7_bios_controller
_os7_bios_controller:
   defs    CRT_COLECO_BIOS_CONTROLLER_SIZE
ENDIF


    ; Disabling-screenmodes hooks (originalmente in coleco_crt0.asm)
    INCLUDE "crt/classic/tms99x8/tms99x8_mode_disable.inc"
