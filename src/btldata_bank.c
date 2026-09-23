// =====================================================================
//  btldata_bank.c -- MegaCart banco 11: TABELLE DI REGOLE della battaglia
// =====================================================================
// Destinato a tutte le tabelle che il motore di battaglia deve consultare
// mentre l'overlay (banco 20) e' mappato: la rodata della slice, che vive
// oltre $C000, in quel momento e' invisibile.
//
// Il codice che le legge sta nel banco FISSO (le svc_), mappa questo banco,
// calcola, e rimette il banco 20 prima di tornare all'overlay.
//
// Contenuto a slice54:
//   curva EXP + dati di passaggio di livello (byte-exact da bank_0B).
// Candidati successivi: enemy_data, formazioni, tabelle della magia.

#define FF1_LEVELUP_DEFINE_DATA
#include "data/levelup_data.h"

// slice55: le statistiche dei 128 nemici (20 byte l'una). Servono a due cose
// nella stessa battaglia -- gli HP di partenza e il bottino -- e sono 2560
// byte, cioe' quanto basta a far saltare il budget della rodata della slice.
#define FF1_ENEMY_DEFINE_DATA
#include "data/enemy_data.h"

// slice60: i dati dei 92 incantesimi/attacchi (8 byte l'uno, 736 in tutto).
// Stessa ragione delle statistiche dei nemici -- li consulta l'overlay, che
// la rodata della slice non la vede -- con in piu' che qui dentro ci sono
// anche le 26 voci degli attacchi speciali dei nemici, cioe' la meta' che
// serve all'IA.
#define FF1_MAGIC_DEFINE_DATA
#include "data/magic_data.h"

// slice60: le 44 voci di IA (16 byte l'una), estratte da
// tools/extract_enemy_ai.ps1. E' la tabella che `Enemy_DoAi` indicizza con
// ENROMSTAT_AI, e senza la quale il nemico puo' solo picchiare.
#define FF1_ENEMY_AI_DEFINE_DATA
#include "data/enemy_ai.h"

// Ri-esportate come simboli globali col prefisso btl_ (gli array negli header
// sono `static` e non finirebbero nel .map). Il main dereferenzia questi
// puntatori DOPO aver mappato il banco 11.
const unsigned char *const btl_exp_to_advance = lut_ExpToAdvance;
const unsigned char *const btl_levelup_data   = data_LevelUpData;
const unsigned char *const btl_hitrate_bonus  = lut_LvlUpHitRateBonus;
const unsigned char *const btl_magdef_bonus   = lut_LvlUpMagDefBonus;
const unsigned char *const btl_enemy_stats    = data_EnemyStats;
const unsigned char *const btl_magic_data     = lut_MagicData;
const unsigned char *const btl_enemy_ai       = lut_EnemyAi;
// slice67: i permessi di magia, 12 classi x 8 livelli. Stanno QUI e non nel
// banco 16 insieme al resto dei negozi per una ragione che non e' di comodo:
// arrivano dallo stesso estratto di lut_MagicData (magic_data.h li definisce
// sotto lo stesso guardiano), e duplicarli in due banchi vorrebbe dire due
// copie che possono divergere. Il negozio di magia paga una seconda escursione
// di banco -- 96 byte copiati una volta per apertura, non una per voce.
const unsigned char *const btl_magic_perm     = lut_MagicPermissions;

// slice68: i 240 nomi, ANCHE qui. Sono gia' nel banco 16 (itemdata_bank.c),
// dove li legge il negozio, e questa e' una seconda copia in ROM -- 1920 byte
// in un banco che ne ha 12000 liberi.
//
// PERCHE' COPIARLI INVECE DI ANDARLI A PRENDERE. Il sottomenu della magia in
// battaglia deve scrivere i nomi degli incantesimi appresi, e il banco 16 da
// li' non si vede. La prima stesura aggiungeva `svc_fetch_item_name` nella
// finestra fissa: **165 byte MISURATI** per copiarne otto, perche' il prezzo
// non e' il ciclo ma il contorno -- salvare e rimettere banco e audio, due
// commutazioni, il preludio di una funzione a due argomenti. Con la finestra
// fissa a 220 byte liberi era i tre quarti di quello che restava.
// Portandoli qui il servizio non serve piu': `svc_fetch_btl` il banco 11 lo
// mappa gia', e aggiungere una tabella e' un `else if`.
//
// LE DUE COPIE NON POSSONO DIVERGERE: nascono dallo stesso header generato
// (src/data/item_names.h), incluso da entrambi i banchi. Sono due copie in
// ROM, una sola nel sorgente.
#define FF1_ITEM_NAMES_DEFINE_DATA
#include "data/item_names.h"
const char *const btl_item_names = ff1_item_names;
// slice74: QUALE icona di tipo porta ogni oggetto. Era gia' qui dentro --
// `ff1_item_icon` sta nello stesso header e sotto la stessa guardia dei nomi --
// e mancava solo il re-export, cioe' il modo di trovarlo dal banco fisso.
//
// SENZA DI ESSO IL MENU NON MOSTRAVA NESSUNA ICONA, e non se n'era accorto
// nessuno: `fetch_name` in ovl_menu.c cercava l'icona DENTRO gli otto byte del
// nome, che e' dove sta nel ROM ma non dove sta qui -- l'estrattore la
// sostituisce con uno spazio e la mette in questa tabella a parte (il commento
// accanto a `ff1_item_icon` in item_names.h lo dice). Il ciclo non trovava mai
// niente e l'icona restava zero. Nello zaino non si vedeva perche' i sei
// consumabili hanno nomi tutti diversi; nella schermata dell'equipaggiamento
// si vedrebbe subito, perche' li' "Iron" e "Iron" sono un'armatura e un elmo.
const unsigned char *const btl_item_icon = ff1_item_icon;

// slice74: i permessi di equipaggiamento, 40 armi + 40 armature, una PAROLA
// l'una (bit acceso = quella classe NON puo'). Anche questi sono una SECONDA
// copia -- l'originale sta nel banco 16, dove li legge il negozio.
//
// PERCHE' UNA COPIA E NON UNA svc_ NUOVA. Il menu deve chiedere il permesso di
// un oggetto QUALUNQUE, a schermata gia' aperta: la strada del negozio -- i
// permessi che viaggiano insieme al listino dentro `SHOP.perm[]` -- li' funziona
// perche' le voci sono cinque e le sceglie il negozio, qui no. Un servizio
// nuovo nella finestra fissa costa ~166 byte misurati (slice60); portarli dove
// `svc_fetch_btl` va gia' costa due `else if`. Stessa mossa dei nomi qui sopra.
//
// LE DUE COPIE NON POSSONO DIVERGERE, per la stessa ragione dei nomi: nascono
// dallo stesso header generato, incluso da entrambi i banchi. Il prezzo vero
// non e' 160 byte ma 640, perche' la guardia che definisce i permessi definisce
// anche le statistiche di armi e armature: separarle vorrebbe dire toccare un
// file generato da import_ff1_data.ps1, cioe' spostare il problema nel
// generatore per risparmiare mezzo per mille di un banco.
#define FF1_WEAPON_DEFINE_DATA
#define FF1_ARMOR_DEFINE_DATA
#include "data/weapon_data.h"
#include "data/armor_data.h"
const unsigned char *const btl_weapon_perms = lut_WeaponPermissions;
const unsigned char *const btl_armor_perms  = lut_ArmorPermissions;

// slice77: i teletrasporti, byte-exact da bank_00.dat (le otto fette in un
// array piatto di 320 byte: tools/extract_teleports.ps1). Stanno QUI e non
// nella rodata della slice per la regola di sempre: li legge il motore delle
// mappe, che quando cambia mappa ha bisogno di dati raggiungibili con una
// escursione sola -- e `svc_fetch_btl` il banco 11 lo mappa gia'. Una tabella
// nuova nel suo dispatch e' un `else if` ([[svc-generalize-rule]]).
#define FF1_TELEPORT_DEFINE_DATA
#include "data/teleport_data.h"
const unsigned char *const btl_teleport = ff1_teleport_data;

// Il linker vuole _main. Mai eseguito: questo banco e' solo dati.
int main(void) { return 0; }
