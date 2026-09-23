// =====================================================================
//  party_state.h -- il gruppo, in RAM SGM a indirizzo fisso
// =====================================================================
// Perche' separato da battle_state.h: il gruppo non appartiene alla battaglia.
// Lo scrive la selezione dei personaggi, lo leggono overworld, citta',
// battaglia e (domani) menu e negozi. La battaglia ne e' solo un lettore.
//
// Sta in RAM SGM perche' quella non dipende dal banco MegaCart: l'overlay di
// battaglia (banco 20) puo' leggerlo senza che nessuno gli passi puntatori.
//
//   $6000-$60FF  stato di battaglia (battle_state.h)
//   $6100-$6BFF  QUI, il gruppo (da slice65 sono 322 byte, non piu' 182:
//                l'intestazione diceva $61FF ed era una sottostima, non un
//                confine -- il vero vicino di casa e' la BSS degli overlay).
//                Da slice71 sono 350: l'inventario sta in coda.
//   $6C00        BSS degli overlay (crt/overlay_crt0.asm)
//
// LAYOUT FEDELE AL NES. I campi sono quelli di `ch_stats` in
// variables.inc:367 (ogni personaggio ha $40 byte sul NES), riempiti da
// NewGame_LoadStartingStats (bank_0F.asm:1811). Tenerli uno a uno serve a due
// cose: le formule del turno fisico leggeranno esattamente cio' che legge il
// NES, e i confronti con l'originale non richiedono conversioni.
//
// exp resta 3 byte come sul NES (FF1 arriva a 999999, che in 16 bit non ci
// sta). Non lo tocca nessuno finche' non arriva la slice di EXP e livelli.
// =====================================================================

#ifndef PARTY_STATE_H
#define PARTY_STATE_H

#define PARTY_STATE_ADDR   0x6100
//   0x9A17 = slice53
//   0x9A18 = slice54 (aggiunto l'oro del gruppo)
//   0x9A19 = slice65 (equipaggiamento, magie apprese, sotto-statistiche base)
//   0x9A1A = slice71 (l'inventario)
#define PARTY_STATE_MAGIC  0x9A1A

#define PARTY_N            4
#define PARTY_NAME_LEN     7      /* 6 caratteri + terminatore */
#define PARTY_SPELL_LEVELS 8      /* il NES tiene le cariche per livello */
#define PARTY_SPELLS_PER_LEVEL 3  /* ch_spells: 3 magie per livello */
#define PARTY_EQUIP_SLOTS  4      /* 4 armi + 4 armature, come sul NES */
#define EQUIP_EQUIPPED     0x80   /* bit 7 del byte di casella */

/* ---- alterazioni di stato (slice69) ---------------------------------------
   Gli stessi otto bit del NES (`Constants.inc:234`), nello stesso ordine. Il
   byte e' `ch_ailments`, cioe' il campo `ailments` qui sotto, e vale ANCHE
   FUORI dalla battaglia: il veleno si porta in giro per la mappa ed e' il
   motivo per cui PURE si vende in negozio.

   Le due maschere composte hanno nomi diversi perche' rispondono a due domande
   diverse, e confonderle e' l'errore che il NES evita scrivendole per esteso
   ogni volta:
     AIL_OUT    "e' fuori dalla battaglia" -- non conta per la fine dello
                scontro, non puo' essere bersaglio, non si rialza da solo.
     AIL_NOACT  "non puo' agire in questo turno" -- comprende i due
                precedenti piu' i due da cui si esce con un tiro (sonno e
                paralisi). Chi e' in AIL_NOACT non riceve nemmeno il menu:
                sul NES e' `AND #AIL_DEAD|AIL_STONE|AIL_STUN|AIL_SLEEP`
                (bank_0C.asm:328 e 560), due punti diversi con la stessa
                maschera. */
#define AIL_DEAD    0x01
#define AIL_STONE   0x02
#define AIL_POISON  0x04
#define AIL_DARK    0x08
#define AIL_STUN    0x10
#define AIL_SLEEP   0x20
#define AIL_MUTE    0x40
#define AIL_CONF    0x80
#define AIL_OUT     (AIL_DEAD | AIL_STONE)
#define AIL_NOACT   (AIL_DEAD | AIL_STONE | AIL_STUN | AIL_SLEEP)

/* Id di classe, come sul NES (CLS_* in Constants.inc) */
#define CLS_FT 0
#define CLS_TH 1
#define CLS_BB 2
#define CLS_RM 3
#define CLS_WM 4
#define CLS_BM 5
#define CLS_KN 6      /* prima classe promossa: il taglio per gli MP iniziali */
#define CLS_MA 8      /* Master = BB promosso (ch_class += 6): stesse regole a mani nude */

typedef struct {
    unsigned char cls;
    unsigned char ailments;
    char          name[PARTY_NAME_LEN];
    unsigned char exp[3];                 /* NES: ch_exp, 3 byte */
    unsigned int  curhp, maxhp;
    /* Statistiche base. `int` e' parola riservata in C: qui int_stat. */
    unsigned char str, agil, int_stat, vit, luck;
    /* Sotto-statistiche. absorb e resist vengono dall'equipaggiamento, non
       dalle stat iniziali: NewGame_LoadStartingStats non le tocca. */
    unsigned char dmg, hitrate, absorb, evade, resist, magdef;
    unsigned char level;                  /* 1-based, come in battaglia sul NES */
    unsigned char curmp[PARTY_SPELL_LEVELS];
    unsigned char maxmp[PARTY_SPELL_LEVELS];

    /* ---- da slice65: equipaggiamento -------------------------------------
       I campi NUOVI stanno IN CODA, e non e' una comodita': gli offset di
       tutto cio' che sta sopra restano quelli di slice54, quindi l'overlay di
       battaglia e le sonde Lua continuano a trovare i campi dove li cercavano.
       L'unica cosa che cambia e' il PASSO fra un personaggio e l'altro -- e
       proprio per questo il gioco adesso lo pubblica in `party_chr_size`,
       invece di lasciarlo cablato negli script (trappola numero 1 del
       catalogo: [[mame-drive-battle-traps]]).

       PERCHE' ESISTONO LE "BASE". dmg, hitrate ed evade sopra sono i valori
       EFFETTIVI, quelli che legge la battaglia. Ma non sono ricavabili da una
       formula: i passaggi di livello li fanno crescere con tiri casuali, e
       quella storia vive solo qui dentro. Se l'equipaggiamento si sommasse
       direttamente sopra di loro, ogni ricalcolo lo sommerebbe una volta di
       piu' -- che e' esattamente il motivo per cui sul NES esistono DUE
       routine gemelle (UnadjustEquipStats toglie, ReadjustEquipStats rimette,
       bank_0F.asm:10854): li' serve poter provare e disfare dentro un menu.
       A noi serve solo il risultato, quindi teniamo la base separata e
       ricalcoliamo l'effettivo da zero. Piu' 3 byte, e un'intera categoria di
       errori che non puo' capitare.
       absorb e resist non hanno una base: senza armatura valgono zero (salvo
       la regola speciale del monaco). */
    unsigned char dmg_b, hitrate_b, evade_b;

    /* Quattro caselle per tipo, come sul NES. Il byte:
         0        = casella vuota
         altro    = indice 1-BASED nella tabella (arma o armatura)
         bit 7    = EQUIPAGGIATO (ReadjustEquipStats salta chi ce l'ha spento)
       Quindi il valore di un'arma indossata e' 0x80 | (id_oggetto - $1B). */
    unsigned char weapon[PARTY_EQUIP_SLOTS];
    unsigned char armor[PARTY_EQUIP_SLOTS];

    /* Magie apprese: 3 caselle per ciascuno degli 8 livelli, come ch_spells.
       Vuote a nuova partita -- in FF1 le magie si COMPRANO, ed e' il motivo
       per cui la magia del giocatore non esiste ancora. */
    unsigned char spells[PARTY_SPELL_LEVELS * PARTY_SPELLS_PER_LEVEL];
} chr_t;

/* PROVATO E NON FUNZIONA: portare la voce da 79 a 80 byte con un byte di
   riempimento, sperando che l'indicizzazione diventasse due scorrimenti invece
   di una moltiplicazione. Misurato: **byte identici**, 15704 di codice in
   entrambi i casi -- sccz80 chiama comunque la sua routine di moltiplicazione
   generica, e la dimensione della voce non la interessa.
   Cio' che PAGA davvero e' prendersi il puntatore al personaggio una volta
   sola (`chr_t *c = &PARTY.chr[i];` e poi `c->campo`) invece di scrivere
   `PARTY.chr[i].campo` a ogni riga: li' la moltiplicazione si fa una volta
   invece che a ogni campo. Vale in tutte le funzioni che toccano piu' di due
   campi dello stesso personaggio. */

/* ---- l'inventario (slice71) -----------------------------------------------
   UNA CASELLA PER ID-OGGETTO, e il contenuto e' la QUANTITA'. Non e' una
   scelta di comodo: e' letteralmente `items` del NES (variables.inc:336, cioe'
   unsram+$20), che copre lo spazio $00-$1B e nient'altro -- armi e armature
   stanno nelle caselle del personaggio, non qui.

   Cosa ne viene, e che una lista di coppie (id, quantita') non darebbe:
     - "quanti ne ho" e "aggiungine uno" sono un accesso diretto, senza
       cercare: il negozio compra in un `if` e tre righe;
     - non esiste il caso "zaino pieno", che sul NES infatti non esiste. Il
       solo limite e' 99 per tipo (ItemShop, bank_0E.asm:4203);
     - gli oggetti chiave sono la stessa cosa dei consumabili con quantita' 0
       o 1, e il menu li mostra con lo stesso ciclo.
   Costa 28 byte fissi contro i ~2 per voce di una lista: a partire da 14
   oggetti diversi in tasca la lista costerebbe di piu', e in FF1 gli oggetti
   chiave da soli sono 17.

   La casella $00 non e' un oggetto e resta sempre zero (sul NES `items+0` non
   ha nome): serve solo a far coincidere l'indice con l'id, che e' tutto il
   punto di questa forma. */
#define INV_COUNT       0x1C   /* $00-$1B, esattamente `item_stop` del NES */
#define INV_MAX_QTY     99     /* ItemShop: CMP #99 prima di comprare */

/* Gli id che questo gioco usa davvero. I chiave sono elencati per intero
   perche' il menu deve saperli nominare, e i sei consumabili in coda sono gli
   unici che una quantita' ce l'hanno davvero. */
#define ITEM_LUTE       0x01
#define ITEM_CROWN      0x02
#define ITEM_CRYSTAL    0x03
#define ITEM_HERB       0x04
#define ITEM_MYSTICKEY  0x05
#define ITEM_TNT        0x06
#define ITEM_ADAMANT    0x07
#define ITEM_SLAB       0x08
#define ITEM_RUBY       0x09
#define ITEM_ROD        0x0A
#define ITEM_FLOATER    0x0B
#define ITEM_CHIME      0x0C
#define ITEM_TAIL       0x0D
#define ITEM_CUBE       0x0E
#define ITEM_BOTTLE     0x0F
#define ITEM_OXYALE     0x10
#define ITEM_CANOE      0x11
#define ITEM_ORB_FIRST  0x12   /* $12-$15: fuoco, acqua, aria, terra */
#define ITEM_TENT       0x16
#define ITEM_CABIN      0x17
#define ITEM_HOUSE      0x18
#define ITEM_HEAL       0x19
#define ITEM_PURE       0x1A
#define ITEM_SOFT       0x1B
/* `item_qty_start` del NES: da qui in poi la quantita' conta davvero. */
#define ITEM_QTY_FIRST  ITEM_TENT

typedef struct {
    unsigned int  magic;
    unsigned char n;
    /* Oro del gruppo, non del singolo. 3 byte come `gold` sul NES: FF1 arriva
       a 999999, e il tetto e' proprio quello del formato. */
    unsigned char gp[3];
    chr_t         chr[PARTY_N];
    /* IN CODA, per la stessa ragione dell'equipaggiamento in slice65: gli
       offset dei personaggi non si spostano, quindi l'overlay di battaglia e
       le sonde Lua continuano a trovare i campi dove li cercavano. La base
       dell'inventario le sonde la ricavano da `party_chr_size`, che il gioco
       gia' pubblica. */
    unsigned char item[INV_COUNT];
} party_t;

#define PARTY (*(party_t *)PARTY_STATE_ADDR)

#endif
