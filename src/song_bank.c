// =====================================================================
//  song_bank.c -- MegaCart banco 10: musiche di battaglia
// =====================================================================
// Perche' un banco suo e non il banco 1 (intro_bank): la NMI audio mappa il
// banco della canzone a ogni tick e poi rimette quello del primo piano. Durante
// la battaglia il primo piano e' l'OVERLAY (banco 20), non il banco 0, quindi
// la musica deve stare in un banco che si possa selezionare senza portarsi
// dietro nient'altro. Tenerla insieme agli asset dell'intro funzionerebbe
// comunque, ma legherebbe due scene che non hanno niente in comune.
//
// Contenuto:
//   sng50 -- Battle (LOOP, 781 eventi). Il tema di battaglia FF1.
//   sng53 -- Victory fanfare (ONE-SHOT). Caricata qui ma NON ancora usata:
//            serve una vittoria, e il motore non sa ancora far morire nessuno.
//            Sta qui perche' costa nulla adesso e risparmia un giro di build
//            quando arrivera' la risoluzione del round.
//
// Compilato con crt/sgm_bank_crt0 (rombase $C000, 16KB). I simboli col
// prefisso `song_` finiscono in song_bank_symbols.h via gen_bank_symbols.ps1.

typedef struct { unsigned int period; unsigned char frames; } note_event_t;

#include "songs/sng50.h"   // Battle
#include "songs/sng53.h"   // Victory fanfare (pronta, non ancora suonata)
// slice77: le musiche delle mappe nuove e la fanfara dei dialoghi. Stanno QUI
// e non nel banco 1 per la stessa ragione di sng50: la NMI deve poterle
// mappare da sole, qualunque cosa sia in primo piano.
// slice77: anche il tema della OVERWORLD sta qui. Viveva nella rodata della
// slice ed era l'ultima canzone fuori da un banco -- il percorso start_song
// che la suonava e' morto, e la tabella song_tbl della slice vuole righe
// uniformi (banco + simboli).
#include "songs/sng44.h"   // Overworld
#include "songs/sng48.h"   // Castle (tileset 1: Coneria Castle 1F/2F)
#include "songs/sng4C.h"   // Temple of Fiends (tileset 5)
#include "songs/sng54.h"   // "got an important item!" -- la fanfara dlgsfx=1
                           // del NES (track $54, bank_0F.asm:5202)
#include "songs/sng51.h"   // Shop + Inn (track $51: sul NES e' la STESSA
                           // musica per le due UI -- catalogo slice18)

// Ri-esportate come simboli globali: gli array negli header sono `static` e
// senza questo non comparirebbero nel .map, quindi il main non saprebbe dove
// sono. Il main dereferenzia questi puntatori DOPO aver mappato il banco 10.
const note_event_t *const song_sng50_sq1 = sng50_sq1;
const note_event_t *const song_sng50_sq2 = sng50_sq2;
const note_event_t *const song_sng50_tri = sng50_tri;
const note_event_t *const song_sng53_sq1 = sng53_sq1;
const note_event_t *const song_sng53_sq2 = sng53_sq2;
const note_event_t *const song_sng53_tri = sng53_tri;
const note_event_t *const song_sng48_sq1 = sng48_sq1;
const note_event_t *const song_sng48_sq2 = sng48_sq2;
const note_event_t *const song_sng48_tri = sng48_tri;
const note_event_t *const song_sng4C_sq1 = sng4C_sq1;
const note_event_t *const song_sng4C_sq2 = sng4C_sq2;
const note_event_t *const song_sng4C_tri = sng4C_tri;
const note_event_t *const song_sng54_sq1 = sng54_sq1;
const note_event_t *const song_sng54_sq2 = sng54_sq2;
const note_event_t *const song_sng54_tri = sng54_tri;
const note_event_t *const song_sng44_sq1 = sng44_sq1;
const note_event_t *const song_sng44_sq2 = sng44_sq2;
const note_event_t *const song_sng44_tri = sng44_tri;
const note_event_t *const song_sng51_sq1 = sng51_sq1;
const note_event_t *const song_sng51_sq2 = sng51_sq2;
const note_event_t *const song_sng51_tri = sng51_tri;

// Il linker vuole _main. Mai eseguito: questo banco e' solo dati.
int main(void) { return 0; }
