// =====================================================================
//  shop_state.h -- il listino del negozio, in RAM SGM a indirizzo fisso
// =====================================================================
// PERCHE' ESISTE. Le tabelle dei negozi stanno nel banco 16, e l'overlay del
// negozio E' un banco: mentre gira, il 16 non e' raggiungibile. La soluzione
// e' la stessa gia' usata per la formazione di battaglia -- una `svc_` nella
// finestra fissa fa l'escursione, compone il listino qui dentro, e l'overlay
// trova tutto in RAM senza sapere niente di banchi.
//
// La divisione del lavoro che ne esce e' anche quella giusta a prescindere:
// nella finestra fissa sta COME si leggono i dati, nell'overlay COME si
// disegnano.
//
// MAPPA DELLA RAM SGM, tenuta qui perche' e' l'ultimo blocco aggiunto:
//   $2000-$5FFF  world_cells, la mappa espansa in celle (16KB pieni)
//   $6000-$60FF  stato di battaglia (battle_state.h)
//   $6100-$62FF  il gruppo (party_state.h) -- ne usa 322 su 512
//   $6300-$63FF  QUI, il listino del negozio
//   $6C00        BSS degli overlay (crt/overlay_crt0.asm)
// =====================================================================

#ifndef SHOP_STATE_H
#define SHOP_STATE_H

#define SHOP_STATE_ADDR   0x6300
//   0x5701 = slice65 (listino: id, prezzo, icona, nome)
//   0x5702 = slice66 (aggiunti i permessi di equipaggiamento)
//   0x5703 = slice67 (aggiunta la tabella dei permessi di MAGIA)
#define SHOP_STATE_MAGIC  0x5703

// Cinque e' il massimo del NES: LoadShopInventory (bank_0E.asm:4871) copia
// esattamente 5 byte. La lista pero' finisce al primo $00 e non lo salta --
// le liste dei negozi si SOVRAPPONGONO, e i byte dopo lo zero sono gia' del
// negozio successivo. Il negozio d'armature di Coneria ne ha 3, non 5.
#define SHOP_MAX_ITEMS  5
#define SHOP_NAME_LEN   8      /* 7 caratteri + terminatore, come nel ROM */

// lut_MagicPermissions: 12 classi (FT TH BB RM WM BM KN NJ MA RW WW BW) x 8
// livelli. Il byte e' il livello, il BIT e' la casella dentro il livello:
// bit 7-4 = magia bianca 0-3, bit 3-0 = magia nera 0-3, e bit ACCESO VIETA.
#define SHOP_MAGIC_CLASSES     12
#define SHOP_MAGIC_LEVELS      PARTY_SPELL_LEVELS
#define SHOP_MAGIC_PERM_BYTES  (SHOP_MAGIC_CLASSES * SHOP_MAGIC_LEVELS)

// lut_ShopTypes. Il negozio 0 non esiste: scarto di uno del NES.
#define SHOPTYPE_WEAPON   0
#define SHOPTYPE_ARMOR    1
#define SHOPTYPE_WMAGIC   2
#define SHOPTYPE_BMAGIC   3
#define SHOPTYPE_CLINIC   4
#define SHOPTYPE_INN      5
#define SHOPTYPE_ITEM     6
#define SHOPTYPE_CARAVAN  7

typedef struct {
    unsigned int  magic;
    unsigned char id;       /* lo shop_id della porta calpestata */
    unsigned char type;     /* SHOPTYPE_* */
    unsigned char count;    /* voci valide; 0 per clinica e locanda */
    /* Clinica e locanda NON hanno un listino: i primi due byte della loro
       lista sono il PREZZO, word LE. Non e' un id di oggetto -- letto come
       tale da una locanda da 5 GP invece che da 30. Vedi bank_0E.asm:4576. */
    unsigned int  service;
    unsigned char item[SHOP_MAX_ITEMS];    /* id-oggetto, spazio $1C-$43 armi ecc. */
    unsigned int  price[SHOP_MAX_ITEMS];
    /* L'icona di TIPO, cioe' il 7o byte del nome nel ROM. 0 = nessuna. Senza
       di essa il negozio d'armi di Coneria mostra "Wooden" due volte. */
    unsigned char icon[SHOP_MAX_ITEMS];
    /* slice66: i permessi di equipaggiamento, una PAROLA per voce.
       Bit ACCESO = quella classe NON puo' (IsEquipLegal, bank_0E.asm:9060), e
       il bit della classe e' `0x800 >> class_id`. Viaggiano col listino perche'
       le due tabelle stanno nel banco 16, che l'overlay non vede: farsele dare
       una voce alla volta avrebbe voluto dire una svc_ nuova.
       0 = nessun divieto (magie e consumabili non hanno permessi). */
    unsigned int  perm[SHOP_MAX_ITEMS];
    char          name[SHOP_MAX_ITEMS * SHOP_NAME_LEN];
    /* slice67: i permessi di MAGIA. Sono un'altra cosa da `perm` qui sopra e
       non si potevano riusare: quelli dipendono dall'OGGETTO (una parola per
       voce, 12 classi), questi dipendono dalla coppia CLASSE x LIVELLO di
       magia -- 12 x 8 byte, e il bit dentro il byte lo sceglie l'incantesimo.
       Si tiene la tabella INTERA invece di ridurla alle 5 voci del listino:
       ridurla vuol dire fare il conto in una `svc_`, cioe' nella finestra
       fissa dove restano poche centinaia di byte, mentre tenerla e' un
       trasferimento e il conto lo fa l'overlay, che di spazio ne ha migliaia.
       A DIFFERENZA DEL RESTO DI QUESTO BLOCCO NON LA RIEMPIE `svc_shop_fetch`:
       la tabella sta nel banco 11 (con lut_MagicData, da cui e' estratta) e
       non nel 16, e l'overlay se la prende da solo con `svc_fetch_btl(3,...)`.
       Vale solo per SHOPTYPE_WMAGIC / SHOPTYPE_BMAGIC: negli altri negozi
       questi byte non li scrive e non li legge nessuno. */
    unsigned char magperm[SHOP_MAGIC_PERM_BYTES];
} shop_t;

/* Bit di permesso di una classe. `lut_ClassEquipBit` sul NES e' una tabella;
   la formula che la genera e' scritta nel commento accanto (bank_0E.asm:9190)
   ed e' esatta per tutte e 12 le classi, promosse comprese. */
#define CLASS_EQUIP_BIT(cls)  ((unsigned int)0x0800 >> (cls))
#define CAN_EQUIP(perm, cls)  (((perm) & CLASS_EQUIP_BIT(cls)) == 0)

#define SHOP (*(shop_t *)SHOP_STATE_ADDR)

#endif
