// =====================================================================
//  battle_ibstats.h -- le statistiche VALIDE PER LA SOLA BATTAGLIA
// =====================================================================
// "IB" e' il nome del NES: `btl_chstats` e `btl_enstats` sono le statistiche
// *in-battle*, contrapposte alle *out-of-battle* di `ch_stats`. Fino a slice69
// questo blocco non esisteva e non serviva: i numeri si leggevano da PARTY
// ($6100) per i personaggi e dalla ROM per i mostri, e nessuno li cambiava.
//
// PERCHE' ADESSO SERVE. Sei effetti di magia su diciotto non toccano HP ne'
// alterazioni: toccano le STATISTICHE. FOG alza l'assorbimento, RUSE
// l'evasione, TMPR la forza, LOCK abbassa l'evasione di un mostro, FAST
// raddoppia i colpi, FEAR il morale. Scritti su PARTY non scadrebbero mai --
// un FOG lanciato una volta varrebbe per il resto della partita -- e scritti
// sulla ROM non si scriverebbero affatto. Serve un terzo posto, che nasce
// all'inizio di ogni battaglia e muore con lei.
//
// I DUE BUG GEMELLI DEL NES, che questo blocco fa sparire tutti e due
// La ROM il blocco ce l'ha, ma lo risalva male, e in modo diverso sui due lati:
//   * `BtlMag_SavePlayerDefenderStats` (bank_0C.asm:8027) NON risalva la
//     FORZA. Percio' TMPR e SABR, che alzano proprio quella, non fanno niente
//     quando sono lanciati su un personaggio -- cioe' sempre, visto che
//     bersagliano chi lancia.
//   * `BtlMag_SaveEnemyDefenderStats` (bank_0C.asm:7982) NON risalva la
//     RESISTENZA ELEMENTALE, che per i mostri resta quella della ROM. Percio'
//     XFER non fa niente sui mostri (fix #6 della lista di intenti).
// Ognuno dei due lati dimentica un campo, e ne dimentica uno diverso. Qui i
// campi sono gli stessi per tutti e due e si scrivono nello stesso modo:
// non c'e' un posto dove dimenticarne uno.
//
// LA STESSA VOCE PER I DUE LATI DEL CAMPO, e non e' un'economia: e' cio' che
// permette a `stat_effect` di essere UNA funzione invece di due. Un
// incantesimo che alza l'evasione fa la stessa cosa a un mago e a un mostro, e
// l'unica differenza -- se atterra -- la decide il chiamante, che e' l'unico a
// sapere da che parte guarda. Due copie di quel conto divergerebbero, e una
// divergenza fra i due lati non si vede giocando: si vede come "i mostri
// resistono di piu'", che e' anche quello che fa un motore giusto.
//
// Mappa della RAM SGM, aggiornata:
//   $2000-$5FFF  buffer celle (world_cells, espansione citta')
//   $6000-$60FF  stato di battaglia (battle_state.h)
//   $6100-$62FF  il gruppo (party_state.h, 322 byte)
//   $6300-$63FF  il negozio (shop_state.h, 173 byte)
//   $6400        QUI, 93 byte
//   $6C00        BSS degli overlay
// =====================================================================

#ifndef BATTLE_IBSTATS_H
#define BATTLE_IBSTATS_H

#define IB_STATE_ADDR   0x6400
//   0x1B70 = slice70 (nascita)
#define IB_STATE_MAGIC  0x1B70

#define IB_CHRS     4
#define IB_ENEMIES  9

/* Il moltiplicatore dei colpi. Uno di base; FAST lo porta a 2 e non oltre
   (`BtlMag_Effect_Fast`, bank_0C.asm:8616: sopra 2 l'incantesimo si dichiara
   NON riuscito, e quel dettaglio conta -- e' la differenza fra "FAST di nuovo"
   e "FAST sprecata"), SLOW lo abbassa. */
#define IB_HITS_MULT_DEFAULT 1
#define IB_HITS_MULT_MAX     2

typedef struct {
    /* Danno base. Per un personaggio e' `ch_dmg` (le basi piu' l'arma, che
       svc_equip_recalc ha gia' composto); per un mostro e' ENROMSTAT_DAMAGE,
       che il NES chiama `en_strength`. Lo alzano TMPR e SABR. */
    unsigned char dmg;
    /* Tiro. Lo alza l'effetto $0D, e solo li' -- vedi la nota su
       stat_effect: sul NES quel ramo scrive in un indirizzo a caso, ma le due
       magie che lo usano hanno tiro zero, quindi il difetto non si e' mai
       visto. Scritto giusto qui non cambia un numero e toglie una domanda. */
    unsigned char hitrate;
    /* Assorbimento: lo alza FOG. */
    unsigned char absorb;
    /* Evasione: la alzano RUSE e INVS, la abbassano LOCK e LOK2. */
    unsigned char evade;
    /* Resistenza elementale, maschera. La accendono AFIR/AICE/ALIT/ARUB/WALL,
       la SPEGNE del tutto XFER. Per un personaggio parte dall'armatura, per un
       mostro da ENROMSTAT_ELEMRESIST. */
    unsigned char resist;
    /* Moltiplicatore dei colpi: FAST e SLOW. */
    unsigned char hits_mult;
    /* Morale, solo per i mostri: lo abbassa FEAR, e a leggerlo e' la fuga
       (`enemy_try_run`). Per un personaggio resta zero e non lo guarda
       nessuno -- tenerlo nella voce comune costa quattro byte in tutto e
       toglie una seconda struct. */
    unsigned char morale;
} ibstat_t;

typedef struct {
    unsigned int magic;
    ibstat_t chr[IB_CHRS];
    ibstat_t en[IB_ENEMIES];
} ibstate_t;

#define IB   (*(ibstate_t *)IB_STATE_ADDR)
#define IBC(i)  (IB.chr[i])
#define IBE(s)  (IB.en[s])

#endif
