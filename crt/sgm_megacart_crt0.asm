;       ColecoVision MegaCart + SGM crt0 -- custom per progetto ColecoFF.
;       Estende sgm_crt0.asm con un bank-switch iniziale: al power-on una
;       MegaCart ha l'ultimo banco visibile in ENTRAMBE le finestre ($8000-
;       BFFF fixed e $C000-$FFFF switchable, default last bank). Il linker
;       z88dk pero' ha generato dati a $C000-$FFFF assumendo cart standard
;       32KB: dobbiamo ridirigere $C000-$FFFF al banco 0 (= primi 16KB del
;       file ROM) PRIMA che il codice acceda a qualunque dato in alto.
;
;       Trigger bank switch (Opcode MegaCart): leggere $FFC0+N seleziona il
;       banco N per la finestra $C000-$FFFF. La lettura ritorna comunque i
;       byte attuali a quell'indirizzo (non un valore "magico"), e' solo
;       l'address decode che attiva lo switch.

    MODULE  coleco_sgm_megacart_crt0

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
    defc    TAR__register_sp = 0x7FFE
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

    defb    0x55, 0xaa
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
    defw    program
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
    jp        asm_im1_handler
ENDIF
IF (__crt_enable_nmi > 1)
    EXTERN        _z80_nmi
    jp        _z80_nmi
ELSE
    jp        nmi_int
ENDIF
    defm        " / / "

restart_ret:
    ret

;; ============================================================
;; MegaCart bank switch + SGM init + standard z88dk init flow
;; ============================================================

program:
    di                              ; mask interrupts during boot

    ;; ---- MegaCart: switch bank 0 into $C000-$FFFF ----
    ;; A power-on, hardware mostra il LAST bank in entrambe le finestre.
    ;; Una lettura a $FFC0+N seleziona il banco N per $C000-$FFFF. Banco 0
    ;; ha i nostri const data (linker output upper half).
    ;; Importante: questo deve avvenire PRIMA di toccare $C000-$FFFF.
    ld      a, ($FFC0)              ; trigger: select bank 0

    ;; ---- Disable VBlank NMI + blank screen (R1 = 0x80) ----
    ld      a, 0x80
    out     (0xBF), a
    ld      a, 0x81
    out     (0xBF), a

    ;; ---- Enable SGM: 24 KB RAM su $2000-$7FFF ----
    ld      a, 0x01
    out     (0x53), a

    ;; ---- Silenzia SN76489 ----
    ld      a, 0x9F
    out     (0xFF), a
    ld      a, 0xBF
    out     (0xFF), a
    ld      a, 0xDF
    out     (0xFF), a
    ld      a, 0xFF
    out     (0xFF), a

    ;; ---- Silenzia AY-3-8910 ----
    ld      a, 0x07
    out     (0x50), a
    ld      a, 0xFF
    out     (0x51), a
    ld      a, 0x08
    out     (0x50), a
    xor     a
    out     (0x51), a
    ld      a, 0x09
    out     (0x50), a
    xor     a
    out     (0x51), a
    ld      a, 0x0A
    out     (0x50), a
    xor     a
    out     (0x51), a

    ;; ---- Standard z88dk init flow ----
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


msxbios:
    push    ix
    ret


l_dcal:
    jp      (hl)

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


    INCLUDE "crt/classic/tms99x8/tms99x8_mode_disable.inc"
