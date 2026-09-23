;       Minimal "data bank" crt0 per ColecoFF MegaCart.
;       Usato per compilare i banchi switchable (intro_bank.c etc) come
;       blob di solo dati linkato a $C000-$FFFF.
;
;       Differenze rispetto a sgm_megacart_crt0.asm:
;       - NESSUN cart header (questo non e' un boot bank)
;       - NESSUN setup SGM/audio/etc (gia' fatto dal main bank's crt0)
;       - Org a $C000 invece di $8000
;       - Nessun _main richiesto -- il bank ha solo dati statici

    MODULE  coleco_sgm_bank_crt0

    defc    crt0 = 1
    INCLUDE "zcc_opt.def"

    PUBLIC  l_dcal
    PUBLIC  __Exit
    defc    CONSOLE_COLUMNS = 32
    defc    CONSOLE_ROWS = 24

    defc    __CPU_CLOCK = 3579545

    ;; BSS irrelevant for a data bank but z88dk still asks for it.
    defc    CRT_ORG_BSS = 0x7000
    defc    CRT_ORG_CODE = 0xC000

    defc    TAR__fputc_cons_generic = 1
    defc    TAR__no_ansifont = 1
    defc    TAR__clib_exit_stack_size = 0
    defc    TAR__register_sp = 0x7FFE
    defc    TAR__crt_enable_eidi = $00
    defc    TAR__crt_on_exit = $0000
    defc    CRT_KEY_DEL = 127
    defc    DEFINED_basegraphics = 0

    INCLUDE "crt/classic/crt_rules.inc"

    org     CRT_ORG_CODE

    ;; Reserve the very first byte so the linker doesn't accidentally
    ;; emit unaligned content. _bank_start serves as a marker for the
    ;; map file (it will be at $C000 if alignment works).
    PUBLIC _bank_start
_bank_start:

__Exit:
    ret

l_dcal:
    jp      (hl)

IFNDEF DEFINED_CRT_FONT
    PUBLIC CRT_FONT
    defc CRT_FONT = 0
ENDIF

    INCLUDE "crt/classic/crt_runtime_selection.inc"

    defc        __crt_org_bss = CRT_ORG_BSS
    IF DEFINED_CRT_MODEL
        defc __crt_model = CRT_MODEL
    ELSE
        defc __crt_model = 1
    ENDIF
    INCLUDE        "crt/classic/crt_section.inc"
