// =====================================================================
//  battle_state.h -- stato di battaglia condiviso fra slice e overlay
// =====================================================================
// Il blocco vive a INDIRIZZO FISSO nella RAM SGM, che non dipende dal banco
// MegaCart: e' l'unico canale valido fra la slice (banco fisso $8000-$BFFF)
// e l'overlay di battaglia (banco 20, $C000-$FFFF). Passare puntatori a
// rodata NON funzionerebbe: la rodata della slice sta nel banco 0, che e'
// invisibile mentre l'overlay e' mappato.
//
// Mappa della RAM SGM (vedi docs/battle_engine_design.md):
//   $2000-$5FFF  buffer celle (world_cells, espansione citta')
//   $6000-$6BFF  LIBERA  <-- qui
//   $6C00-$6FFF  BSS degli overlay
//   $7000+       BSS della slice principale
//   $7FFE        stack
//
// La struct e' compilata dallo STESSO compilatore da entrambe le parti, quindi
// il layout coincide per costruzione. Il campo `magic` serve da prova a
// schermo che la slice ha davvero scritto il blocco prima di chiamare
// l'overlay: se l'overlay legge altro, lo dice invece di disegnare spazzatura.
// =====================================================================

#ifndef BATTLE_STATE_H
#define BATTLE_STATE_H

#define BATTLE_STATE_ADDR   0x6000
// REGOLA: cambiare il layout della struct = cambiare il magic. La slice e
// l'overlay sono due compilazioni separate; se qualcuno ne ricostruisce una
// sola, il magic non torna e l'overlay lo dice a schermo invece di leggere i
// campi agli offset sbagliati. Senza questo, il sintomo sarebbe spazzatura
// silenziosa -- la famiglia di bug che questo progetto ha gia' pagato caro.
//   0xB471 = slice52 (formation, domain, party inline)
//   0xB472 = slice53 (il gruppo si e' spostato in party_state.h)
//   0xB473 = slice54 (esito delle ricompense di fine battaglia)
//   0xB474 = slice55 (formazione decodificata: tipi, nemici, HP)
//   0xB475 = slice55 (i 16 byte grezzi in coda: la decodifica passa all'overlay)
//   0xB476 = slice56 (nemici grandi: type_tile_base, allocazione non piu' fissa)
//   0xB477 = slice57 (turno fisico: azioni scelte, bersagli, fase)
//   0xB478 = slice59 (ordine di iniziativa: la coda dei 13 turni)
//   0xB479 = slice60 (posizioni dell'IA: le caselle di magia e attacco)
//   0xB47A = slice60 (sonda dei lanci: quanti e quale)
//   0xB47B = slice68 (magia del giocatore: l'incantesimo scelto da ciascuno)
//   0xB47C = slice69 (alterazioni di stato dei nemici)
//   0xB47D = slice69 (le tre sonde delle alterazioni)
//   0xB47E = slice70 (le due sonde dei potenziamenti)
#define BATTLE_STATE_MAGIC  0xB47E

#define BST_N_CLASSES 6

/* Nove nemici piccoli: e' il massimo del tipo di formazione "9small", cioe'
   lut_EnemyCountByBattleType[0]. Quattro tipi: i gruppi della formazione sono
   sempre 4 (byte 2-5 dei 16). */
#define BST_MAX_ENEMIES 9
#define BST_MAX_TYPES   4
#define BST_NO_ENEMY    0xFF

/* ---- il bilancio delle tile dei mostri ---------------------------------
   Stavano in tre posti (la slice, l'overlay di battaglia e -- da slice69 --
   quello della magia, che alloca): tre copie di un confine di VRAM sono tre
   occasioni di divergere, e chi le fa divergere non vede un errore di
   compilazione, vede il font sovrascritto. Qui una volta sola.
   $A4-$FF sono le 92 tile che restano dopo font e sagome del gruppo; un mostro
   piccolo ne chiede 16, uno grande 36. Il massimo misurato su tutte e 256 le
   formazioni e' 72 (tools/census_tile_budget.ps1). */
#define MON_TILE_BASE   0xA4
#define MON_TILE_END    0x100
#define MON_TILES       16
#define MON_TILES_LARGE 36

/* Tipi di battaglia, dal nibble alto del byte 0 della formazione. */
#define BTL_TYPE_9SMALL 0
#define BTL_TYPE_4LARGE 1
#define BTL_TYPE_MIX    2
#define BTL_TYPE_FIEND  3
#define BTL_TYPE_CHAOS  4

/* Valori di ritorno di overlay_main */
#define BATTLE_RESULT_ESCAPE  1
#define BATTLE_RESULT_VICTORY 2
#define BATTLE_RESULT_DEFEAT  3

/* La coda dei turni: 9 slot nemico + 4 personaggi, come lut_InitialTurnOrder
   (`bank_0C.asm:3181`). I personaggi hanno il bit 7 acceso, ed e' cosi' che il
   NES distingue le due parti con un solo BMI. */
#define BST_TURN_ENTRIES  13
#define BST_TURN_IS_CHR   0x80

/* Solo cio' che appartiene ALLA BATTAGLIA. Le statistiche dei personaggi
   stanno in party_state.h ($6100) e la battaglia le legge da la': duplicarle
   qui vorrebbe dire ricopiarle a ogni ingresso e riscriverle all'uscita. */
typedef struct {
    unsigned int  magic;                          /* BATTLE_STATE_MAGIC */
    unsigned char formation;                      /* id formazione NES */
    unsigned char domain;                         /* dominio di encounter */
    /* Riempito da svc_battle_load_gfx leggendo il banco 2: l'overlay non puo'
       mappare il banco 2 da solo, verrebbe smontato mentre gira. */
    unsigned char accent_color[BST_N_CLASSES];
    unsigned char turn_chr;
    unsigned char command_idx;
    unsigned int  round_num;
    unsigned char result;
    /* INGRESSO di svc_award_exp: il bottino TOTALE della battaglia, che la
       slice calcola prima di entrare nell'overlay. Finche' i nemici non sono
       veri e' un valore di prova. */
    unsigned int  exp_total;
    unsigned int  gp_total;
    /* USCITA di svc_award_exp, che l'overlay stampa nel riquadro di fine
       battaglia. exp_award e' la quota GIA' divisa fra i superstiti: il NES
       divide gli EXP, l'oro no. new_level[i] = 0 se quel personaggio non e'
       salito, altrimenti il livello raggiunto. */
    unsigned int  exp_award;
    unsigned int  gp_award;
    unsigned char new_level[4];

    /* ---- formazione decodificata (slice55) ------------------------------
       La riempie fill_battle_state nella slice, dove il banco 0 e' mappato e
       quindi ff1_battle_formations si puo' leggere. L'overlay la trova gia'
       pronta: da li' la tabella non sarebbe visibile.

       "tipo" = gruppo della formazione che ha generato almeno un nemico. Sono
       al massimo 4 e ognuno costa tile in VRAM -- 16 se piccolo, 36 se grande
       -- per questo il numero e' fisso e non cresce col numero di nemici:
       cinque IMP sono UN tipo. */
    unsigned char btl_type;                   /* BTL_TYPE_* */
    unsigned char chr_page;                   /* pagina CHR dei nemici, 0-15 */
    unsigned char no_run;                     /* la formazione vieta la fuga */
    unsigned char n_types;
    unsigned char type_gfx[BST_MAX_TYPES];    /* slot grafico 0-3 dal byte 1 */
    unsigned char type_pal[BST_MAX_TYPES];    /* id palette 0-63 */
    unsigned char type_enemy[BST_MAX_TYPES];  /* id nemico 0-127 */
    /* Prima tile VRAM del tipo. Fino a slice55 era MON_TILE_BASE + t*16, cioe'
       quattro fette fisse; da slice56 non lo puo' piu' essere, perche' un tipo
       grande ne occupa 36 e uno piccolo 16. Lo calcola decode_formation
       nell'overlay -- l'unico posto che sa quali tipi sono davvero in campo --
       e svc_battle_load_enemy_gfx lo legge invece di ricalcolarlo, cosi' i due
       lati non possono divergere. 0xFF = tipo che non ci sta (non accade con
       le formazioni vere: il massimo misurato e' 72 tile su 92). */
    unsigned char type_tile_base[BST_MAX_TYPES];
    /* Il nome sta QUI, gia' convertito, e non lo si va a leggere al momento
       di stamparlo: ff1_enemy_names e' rodata della slice, cioe' banco 0, e
       dall'overlay sarebbe spazzatura. 9 byte = 8 caratteri + terminatore,
       il massimo di DrawBattleSubString_Max8. */
    char          type_name[BST_MAX_TYPES][9];

    unsigned char n_enemies;
    unsigned char enemy_type[BST_MAX_ENEMIES];  /* indice di tipo o BST_NO_ENEMY */
    unsigned int  enemy_hp[BST_MAX_ENEMIES];

    /* I 16 byte grezzi della formazione, prelevati dal banco 12 da
       svc_battle_fetch_formdata. Passano da qui perche' la DECODIFICA gira
       nell'overlay: il banco fisso era pieno (vedi la nota in ovl_battle.c) e
       l'overlay non puo' mappare un banco da solo. */
    unsigned char formdata[16];

    /* ---- turno fisico (slice57) -----------------------------------------
       In coda alla struct di proposito: tutti gli offset precedenti restano
       dove sono, e le sonde gia' cablate in tools/mame_drive_battle.lua non
       vanno rifatte. Cambia solo il magic.

       Le azioni si RACCOLGONO prima e si risolvono dopo, invece di eseguire
       subito a ogni conferma. E' obbligatorio, non una preferenza: il salto
       diretto al personaggio col tastierino ($1-$4) rompe l'ordine lineare,
       quindi "e' il turno di X" non e' piu' una posizione in una sequenza ma
       uno stato per ciascuno. Il round parte quando tutti i vivi hanno scelto.
       Vedi [[battle-round-start-todo]]. */
    unsigned char phase;                       /* BPHASE_* */
    unsigned char cursor_tgt;                  /* slot nemico sotto il cursore */
    unsigned char chr_cmd[4];                  /* comando scelto */
    unsigned char chr_tgt[4];                  /* slot nemico bersaglio */
    unsigned char chr_chosen[4];               /* 0 = deve ancora scegliere */

    /* ---- ordine di iniziativa (slice59) ---------------------------------
       Di nuovo in coda, di nuovo per non spostare gli offset gia' cablati in
       tools/mame_drive_battle.lua.

       Vive in BST e non fra le variabili dell'overlay per una ragione sola,
       ma buona: e' la cosa meno osservabile del round. Un ordine sbagliato non
       si vede a schermo -- si vede come "a volte il nemico picchia due volte
       di fila", che e' anche cio' che fa un ordine GIUSTO. Da qui la sonda
       Lua lo legge e lo confronta, invece di doverlo dedurre. */
    unsigned char turn_order[BST_TURN_ENTRIES];
    unsigned char cur_turn;

    /* ---- posizioni dell'IA nemica (slice60) -----------------------------
       `en_aimagpos` / `en_aiatkpos` del NES (variables.inc:724-725), uno per
       SLOT e non per tipo: due IMP della stessa specie scorrono le proprie
       caselle in modo indipendente, ed e' cosi' anche sull'originale perche'
       il contatore vive nella RAM del singolo nemico.

       Vanno azzerati all'inizio di ogni battaglia: sopravvivono nella RAM SGM
       e senza, il primo incantesimo del secondo incontro ripartirebbe da dove
       era arrivato il primo. */
    unsigned char enemy_aimagpos[BST_MAX_ENEMIES];
    unsigned char enemy_aiatkpos[BST_MAX_ENEMIES];
    /* Contatore dei lanci e id dell'ultimo. Non sono per il gioco: sono per il
       test. Un incantesimo nemico si vede a schermo per 30 frame e poi non
       lascia traccia -- se il ramo dell'IA non partisse mai, la battaglia
       sarebbe identica a una in cui non e' mai uscito il tiro. Come per
       l'ordine di iniziativa, cio' che non si distingue a occhio va letto
       dalla RAM. */
    unsigned char cast_count;
    unsigned char last_spell;

    /* ---- magia del giocatore (slice68) ----------------------------------
       In coda come tutto il resto, per non spostare gli offset gia' cablati
       nelle sonde Lua.

       `chr_spell[i]` e' l'id di magia 0-63 scelto da i, valido solo se
       `chr_cmd[i]` vale BCMD_MAGIC. NON e' il byte di `ch_spells`: quello dice
       QUALE DEGLI OTTO incantesimi del livello (1-8) e da solo non basta a
       trovare la voce in tabella. La conversione e' quella del NES
       (`ConvertOBStatsToIB`, bank_0B.asm:379): `id = livello*8 + (valore-1)`.

       `chr_tgt[i]` porta il bersaglio nella CODIFICA DEL NES
       (`SetCharacterBattleCommand`, bank_0C.asm:775-820), che vale per tutti
       i comandi e non solo per la magia:
           0x00-0x08  slot di un nemico
           0x80|n     il personaggio n
           0xFE       tutto il gruppo
           0xFF       tutti i nemici
       piu' un valore nostro che il NES non ha bisogno di scrivere da nessuna
       parte, perche' li' il cursore sui nemici gira DENTRO il sottomenu:
           0xFD       "va scelto un nemico" -- il sottomenu ha finito e la
                      scelta tocca all'overlay di battaglia, che il cursore
                      sull'arena ce l'ha gia' per il comando FIGHT.
       Farlo scegliere di la' e' cio' che tiene la geometria dell'arena in UN
       solo overlay: duplicarla nel secondo vorrebbe dire due copie che
       possono divergere, e un cursore che punta il mostro sbagliato non
       somiglia a un difetto -- somiglia a una magia che ha mancato. */
    unsigned char chr_spell[4];
    /* Sonda: quante magie ha lanciato il GRUPPO e l'ultima, gemelle di
       cast_count/last_spell che contano quelle dei nemici. Stessa ragione:
       un incantesimo che non parte e uno che parte e non fa niente si
       somigliano a schermo. */
    unsigned char pc_cast_count;
    unsigned char pc_last_spell;

    /* ---- alterazioni di stato dei nemici (slice69) -----------------------
       In coda, come tutto quello che e' arrivato dopo, per non spostare gli
       offset gia' cablati nelle sonde Lua.

       I nemici hanno bisogno di un posto in RAM e i personaggi no, perche' i
       personaggi il loro byte ce l'hanno gia' in party_state.h ($6100) e se lo
       portano fuori dalla battaglia. Un mostro invece esiste solo qui: le sue
       statistiche stanno in ROM (banco 11) e la ROM non si scrive. E' lo stesso
       motivo per cui sul NES l'`en_ailments` sta nella RAM della battaglia, ed
       e' anche la ragione del bug di XFER -- li' la resistenza elementale del
       mostro e' rimasta in ROM, quindi modificarla non serve a niente
       (bank_0C.asm:8740). Qui non ricadremo nello stesso errore per le
       alterazioni; per la resistenza, quando servira', ci vuole un array come
       questo.

       Azzerato all'ingresso in battaglia, non alla fine: la RAM SGM non la
       pulisce nessuno, e senza, il primo mostro del secondo incontro si
       sveglierebbe addormentato. */
    unsigned char enemy_ail[BST_MAX_ENEMIES];

    /* Le tre sonde delle alterazioni. Non sono per il gioco, sono per il test,
       e senza di loro meta' di slice69 non si puo' provare:

       un mostro che si addormenta e si sveglia nel proprio turno dello STESSO
       round non lascia niente dietro di se'. A fine round `enemy_ail` e' zero
       tanto se SLEP ha preso quanto se non e' mai partita, e a schermo la
       differenza sono due righe di messaggio che passano in un secondo. E' la
       stessa situazione dei lanci nemici in slice60 e dell'ordine di iniziativa
       in slice59, e la risposta e' la stessa: cio' che non si distingue a
       occhio si mette in RAM e lo legge la sonda.

       `ail_set` conta le alterazioni ANDATE A SEGNO, da qualunque parte del
       campo e per qualunque strada (incantesimo o colpo); `ail_last` e'
       l'ultima maschera applicata; `ail_turns` conta i turni persi per sonno,
       paralisi o confusione -- cioe' quante volte il tiro del risveglio ha
       davvero girato. */
    unsigned char ail_set;
    unsigned char ail_last;
    unsigned char ail_turns;
    /* Gli HP tolti dal VELENO in questa battaglia. Serve perche' il veleno e'
       l'unica alterazione che si legge come un numero, e proprio per questo
       sarebbe l'unica indistinguibile: due HP in meno a fine round sono anche
       quello che fa un colpo andato a segno. Contati a parte, diventano
       esattamente 2 per round per avvelenato vivo -- una condizione che si puo'
       affermare invece che osservare. */
    unsigned char ail_poison;

    /* ---- sonde dei potenziamenti (slice70) -------------------------------
       Gemelle di `ail_set`/`ail_last`, e nate dallo stesso problema: FOG alza
       l'assorbimento di otto, e otto punti di assorbimento non si vedono a
       schermo -- si vedono come "quel colpo ha fatto meno danno", che e' anche
       quello che fa un tiro fortunato. Il numero vero sta nel blocco IB
       (`battle_ibstats.h`) e la sonda lo legge di la'; questi due contano
       QUANTI effetti sulle statistiche hanno morso e qual e' stato l'ultimo,
       che e' l'altra meta' della domanda. */
    unsigned char buff_set;
    unsigned char buff_last;
} battle_state_t;

/* Comandi, come li numera il menu (l'ordine e' quello del NES). Fino a
   slice67 esisteva solo il primo e il confronto era scritto `!= 0`. */
#define BCMD_FIGHT  0
#define BCMD_MAGIC  1
#define BCMD_DRINK  2
#define BCMD_ITEM   3
#define BCMD_RUN    4

/* Bersagli speciali, vedi la nota su chr_tgt. */
#define BTGT_PICK_FOE   0xFD
#define BTGT_ALL_ALLIES 0xFE
#define BTGT_ALL_FOES   0xFF
#define BTGT_IS_CHR     0x80

/* L'overlay della magia (banco 23) si entra con `svc_run_overlay(23, arg)`:
   il byte basso e' il personaggio, il byte alto dice cosa fare.
   Uno solo per due mestieri e non due overlay, perche' i due mestieri hanno
   bisogno delle stesse cose -- la tabella degli incantesimi, i nomi dal banco
   16, gli stessi conti -- e separarli vorrebbe dire duplicarle. */
#define BTLMAG_MODE_SELECT  0x0000
#define BTLMAG_MODE_CAST    0x0100
/* Terzo mestiere (slice69): il turno di chi non puo' agire -- il tiro per
   svegliarsi, quello per scrollarsi la paralisi, e il messaggio che ne segue.
   Sta li' e non nell'overlay di battaglia per due ragioni che tirano nella
   stessa direzione: nel banco 20 non c'e' piu' posto, e il tiro e' lo STESSO
   per un personaggio e per un mostro. Due copie divergerebbero, e una
   divergenza fra le due parti del campo non si vede giocando -- si vede come
   "i mostri si svegliano prima", che e' anche quello che fa una copia giusta.
   Il byte basso dice CHI: 0x80|n il personaggio n, altrimenti lo slot nemico.
   E' la stessa codifica di chr_tgt, e non per caso: e' la codifica del NES. */
#define BTLMAG_MODE_AILTURN 0x0200
/* Quarto mestiere (slice69): il lancio dalla parte dei MOSTRI, che fino a
   slice68 stava nell'overlay di battaglia. Byte basso = slot del lanciatore;
   l'id dell'incantesimo si legge da `last_spell`, che il banco 20 scrive
   prima di entrare (nell'argomento c'e' posto per un byte solo).
   Il valore di ritorno e' la MASCHERA dei personaggi toccati, un bit per
   ciascuno: qui dentro non si sa dove stiano le sagome, quindi il lampeggio lo
   fa chi ha chiamato. */
#define BTLMAG_MODE_ENEMYCAST 0x0300
/* Quinto mestiere, e il piu' lontano dalla magia (slice69): la PREPARAZIONE
   della battaglia -- decodifica della formazione e caricamento di nomi, HP e
   bottino. Sta li' per una ragione sola e onesta: erano 1402 byte in un banco
   pieno, e sono codice che non tocca ne' schermo ne' sprite, quindi puo' stare
   ovunque. Il byte basso non serve.
   Va chiamata DOPO svc_battle_fetch_formdata (che porta i 16 byte grezzi) e
   PRIMA di svc_battle_load_enemy_gfx (che legge type_tile_base). */
#define BTLMAG_MODE_SETUP     0x0400
/* Sesto mestiere, e il piu' lontano di tutti (slice76): le RICOMPENSE. EXP,
   oro e passaggi di livello, cioe' `svc_award_exp` e `level_up_one`, che fino a
   slice75 stavano nella finestra fissa -- **1539 byte** per girare una volta
   per battaglia vinta. Sono la leva 1 di [[fixed-window-full]] applicata al
   caso rimasto piu' vistoso dopo party_init (slice72).
   Sta QUI e non in un banco nuovo perche' l'overlay di battaglia questo lo
   chiamava gia': nessuna strada nuova, un `else if` nel dispatch.
   Ingresso e uscita passano da BST come prima. Il byte basso non serve. */
#define BTLMAG_MODE_AWARDEXP  0x0500
/* Valore di ritorno della scelta: byte alto = bersaglio, byte basso = id di
   magia. Questo intero non puo' essere un bersaglio valido. */
#define BTLMAG_CANCELLED    0xFFFF

/* Fasi dell'interfaccia di battaglia. */
#define BPHASE_CMD     0    /* si sceglie il comando */
#define BPHASE_TARGET  1    /* si sceglie il bersaglio */

#define BST (*(battle_state_t *)BATTLE_STATE_ADDR)

#endif
