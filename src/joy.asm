; joy.asm -- lettura joystick+tastierino del giocatore 1, SICURA SOTTO OVERLAY.
;
; PERCHE' NON SI USA joystick(3) DELLA LIBRERIA
;   coleco_joypad.asm tiene la tabella di decodifica del tastierino
;   (button_mapping) in SECTION rodata_clib. Nel link della slice quella
;   sezione finisce oltre $C000 -- in slice52 a $E890 -- cioe' nella finestra
;   COMMUTABILE. Chiamata dal banco fisso col banco 0 mappato funziona; ma
;   l'overlay di battaglia gira col banco 20 mappato, e la stessa lettura
;   restituirebbe byte del banco 20 interpretati come codice tasto. Il salto
;   diretto al personaggio col tastierino (1-4) leggerebbe spazzatura.
;
;   I bit del joystick invece si costruiscono con `set` immediati, senza
;   tabella: quelli sarebbero sopravvissuti. E' solo il tastierino a rompersi
;   -- il tipo di bug che non da' errore e si nota mesi dopo.
;
;   Qui tabella e codice stanno entrambi in SECTION code_user, che il linker
;   piazza nella finestra FISSA $8000-$BFFF: leggibile qualunque banco sia
;   selezionato. Stessa regola d'oro delle svc_ (vedi crt/overlay_crt0.asm).
;
; Ritorno (identico a joystick(3) di z88dk, cosi' il codice chiamante non cambia):
;   L = bit del joystick   1=RIGHT 2=LEFT 4=DOWN 8=UP 16=FIRE1 32=FIRE2
;   H = codice ASCII del tasto del tastierino premuto, 0 se nessuno

    SECTION code_user

    PUBLIC  _joy_read_p1

; unsigned int joy_read_p1(void)
_joy_read_p1:
    ld      bc, $00FC           ; porta del giocatore 1 (B=0 sulle linee alte,
    ld      a, 1                ; come fa la libreria: `in a,(c)`, non `in a,(n)`)
    out     ($C0), a            ; modo joystick
    in      a, (c)
    ld      l, 0                ; gli ingressi Coleco sono attivi BASSI
    bit     0, a
    jr      nz, joy_nup
    set     3, l                ; MOVE_UP
joy_nup:
    bit     1, a
    jr      nz, joy_nrt
    set     0, l                ; MOVE_RIGHT
joy_nrt:
    bit     2, a
    jr      nz, joy_ndn
    set     2, l                ; MOVE_DOWN
joy_ndn:
    bit     3, a
    jr      nz, joy_nlf
    set     1, l                ; MOVE_LEFT
joy_nlf:
    bit     6, a
    jr      nz, joy_nf2
    set     5, l                ; MOVE_FIRE2 (pulsante destro)
joy_nf2:
    ld      a, 1
    out     ($80), a            ; modo tastierino
    in      a, (c)
    bit     6, a
    jr      nz, joy_nf1
    set     4, l                ; MOVE_FIRE1 (pulsante sinistro)
joy_nf1:
    ld      e, l                ; L serve ancora: `ld hl,tab` lo distruggerebbe
    and     $0F
    ld      c, a
    ld      b, 0
    ld      hl, joy_keymap
    add     hl, bc
    ld      h, (hl)             ; H = codice tasto
    ld      l, e                ; L = bit joystick
    ret

; Indice = nibble basso della porta in modo tastierino. $0 e $F = niente premuto.
joy_keymap:
    defb    $00                 ; 0
    defb    $38                 ; 1 -> '8'
    defb    $34                 ; 2 -> '4'
    defb    $35                 ; 3 -> '5'
    defb    $43                 ; 4 -> 'C'  (tasto F4)
    defb    $37                 ; 5 -> '7'
    defb    $23                 ; 6 -> '#'
    defb    $32                 ; 7 -> '2'
    defb    $44                 ; 8 -> 'D'  (tasto F3)
    defb    $2A                 ; 9 -> '*'
    defb    $30                 ; a -> '0'
    defb    $39                 ; b -> '9'
    defb    $33                 ; c -> '3'
    defb    $31                 ; d -> '1'
    defb    $36                 ; e -> '6'
    defb    $00                 ; f
