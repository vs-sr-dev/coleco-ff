// =====================================================================
//  itemdata_bank.c -- BANCO 16: oggetti, negozi, nomi, icone
// =====================================================================
// Tutto cio' che serve a un negozio per esistere, in un banco solo:
//
//   lut_WeaponData        40 armi x 8 byte      (hit, danno, critico, ...)
//   lut_WeaponPermissions 40 x 2 byte           (bit acceso = NON puo')
//   lut_ArmorData         40 armature x 4 byte  (evade, assorbimento, resist)
//   lut_ArmorPermissions  40 x 2 byte
//   lut_ItemPrices        240 word LE
//   lut_ShopData          71 puntatori + le liste in linea
//   lut_ShopTypes         71 byte, uno per negozio
//   ff1_item_names        240 nomi da 8 byte    (1920 byte, il piu' grosso)
//   ff1_item_icon         240 byte, l'icona di ogni oggetto (0 = nessuna)
//   ff1_item_icons        12 tile da 8 byte     (le icone di TIPO)
//
// PERCHE' STANNO INSIEME, e non sparsi come sarebbe venuto naturale: una
// voce di negozio si compone di quattro pezzi -- l'id nella lista, il nome,
// il prezzo, l'icona -- e disegnarne una riga vuol dire leggerli tutti e
// quattro. Se vivessero in banchi diversi, ogni riga di listino costerebbe
// tre commutazioni, ognuna una possibilita' di leggere il banco sbagliato.
// Qui se ne mappa UNO.
//
// LE ICONE NON SONO UN ORNAMENTO. Il 7o byte di ogni nome e' l'icona del
// tipo; senza, il negozio d'armi di Coneria mostra
//     Wooden / Small / Wooden / Rapier / Iron
// cioe' due voci identiche nella stessa lista. Fra le armature e' peggio
// ("Opal" cinque volte). E' un prerequisito dell'interfaccia, non un rifinire.
//
// I re-export sono `const unsigned char *const`: puntatori in RODATA, MAI
// array multidimensionali -- quelli finirebbero in DATA, che in un banco non
// viene mai copiata in RAM (bug #3 di slice44, [[slice44-real-root-causes]]).
// Per la stessa ragione tutti gli array qui sotto sono PIATTI: l'indicizzazione
// la fanno le macro degli header (`&ff1_item_names[id * 8]`).
// =====================================================================

#define FF1_WEAPON_DEFINE_DATA
#define FF1_ARMOR_DEFINE_DATA
#define FF1_SHOP_DEFINE_DATA
#define FF1_ITEM_NAMES_DEFINE_DATA
#define FF1_ITEM_ICONS_DEFINE_DATA
#include "data/weapon_data.h"
#include "data/armor_data.h"
#include "data/shop_data.h"
#include "data/item_names.h"
#include "ff1_item_icons.h"

const unsigned char *const itemdata_weapons      = lut_WeaponData;
const unsigned char *const itemdata_weapon_perms = lut_WeaponPermissions;
const unsigned char *const itemdata_armor        = lut_ArmorData;
const unsigned char *const itemdata_armor_perms  = lut_ArmorPermissions;
const unsigned char *const itemdata_prices       = lut_ItemPrices;
const unsigned char *const itemdata_shopdata     = lut_ShopData;
const unsigned char *const itemdata_shoptypes    = lut_ShopTypes;
const char          *const itemdata_names        = ff1_item_names;
const unsigned char *const itemdata_icons        = ff1_item_icons;
// Quale icona porta ogni oggetto. Senza questa, avere le tile non basta.
const unsigned char *const itemdata_icon_of      = ff1_item_icon;

int main(void) { return 0; }
