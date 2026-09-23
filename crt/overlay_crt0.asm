;       ColecoFF -- crt0 per OVERLAY DI CODICE in un banco MegaCart.
;
;       Perche' esiste: la finestra fissa $8000-$BFFF e' 16KB e NON e'
;       paginabile, quindi il codice del gioco ha un tetto duro di 16KB.
;       slice44 ne usa gia' ~14KB. Il motore di battaglia / negozi / menu
;       non ci stanno. Un overlay e' un blocco di CODICE compilato per
;       girare a $C000-$FFFF dentro un banco commutabile: il main lo
;       seleziona e lo chiama, l'overlay gira, ritorna, il main ripristina
;       il banco precedente.
;
;       Differenze rispetto a sgm_bank_crt0.asm (che e' per soli DATI):
;       - Il PRIMISSIMO byte a $C000 e' `jp _overlay_main`, cosi' il main
;         puo' chiamare l'overlay a un indirizzo COSTANTE ($C000) senza
;         dover leggere la .map dell'overlay. Questo rompe la dipendenza
;         circolare main<->overlay: solo l'overlay ha bisogno degli
;         indirizzi del main (via tools/gen_bank_symbols.ps1 -Prefix svc_),
;         mai il contrario.
;       - Nessun init: SGM, VDP, audio e stack li ha gia' preparati il
;         crt0 del banco fisso. L'overlay eredita tutto.
;       - `ret` di _overlay_main torna direttamente al chiamante nel banco
;         fisso: l'indirizzo di ritorno e' sullo stack (RAM SGM, che non
;         dipende dal banco) e punta a $8000-$BFFF, sempre visibile.
;
;       REGOLA D'ORO: mentre un overlay e' mappato, la rodata del banco 0
;       e' INVISIBILE. Le funzioni di servizio nel banco fisso chiamate
;       dall'overlay non devono toccare dati del banco 0.

    MODULE  coleco_overlay_crt0

    defc    crt0 = 1
    INCLUDE "zcc_opt.def"

    EXTERN  _overlay_main

    PUBLIC  l_dcal
    PUBLIC  __Exit
    defc    CONSOLE_COLUMNS = 32
    defc    CONSOLE_ROWS = 24

    defc    __CPU_CLOCK = 3579545

    ;; BSS dell'overlay: condivide la RAM SGM col main. Va tenuto ALTO e
    ;; separato dal BSS del main per non sovrapporsi -- vedi la nota in
    ;; docs/ o nella memoria [[code-overlay-architecture]].
IF !DEFINED_CRT_ORG_BSS
    defc    CRT_ORG_BSS = 0x6C00
ENDIF
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

    ;; ---- PUNTO DI INGRESSO FISSO: $C000 ----
    PUBLIC _bank_start
_bank_start:
    jp      _overlay_main

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
