# Motore di battaglia — piano di attacco (blocco B)

Documento di consegna scritto a fine sessione 12, quando l'architettura dei
banchi era ancora calda. Serve a far partire la sessione successiva da un
piano invece che da un'esplorazione.

## Stato di partenza

Quello che c'è già e funziona:

- **Schermata di battaglia NES-parity** (slice24-35): sprite dei 4 personaggi
  a colori, striscia statistiche, box comandi, area mostri, banda di sfondo.
  Vive in `slice49.c`, funzioni `render_battle_screen` / `battle_tick`.
- **Encounter byte-parity**: `compute_domain` + `get_battle_formation` +
  `battle_step_rng` producono la stessa formazione che darebbe il NES.
  Confermato funzionante dall'utente in sessione 12.
- **Dati importati e mai usati**, in `src/data/`: `enemy_data.h` (3713 byte),
  `class_stats.h` (96), `magic_data.h` (832), `weapon_data.h` (406),
  `armor_data.h` (240), `shop_data.h` (935).

Quello che manca è **tutta la logica**: `battle_tick` è una scaffold di
interfaccia. FIRE1 stampa "CHR1 > FIGHT" e passa al personaggio dopo. Nessun
danno, nessun nemico che agisce, nessuna vittoria.

## Dove va il codice

Il motore va in un **overlay** (`ovl_battle.c`, banco 20), non nel banco fisso:
là restano solo 1720 byte liberi e il motore ne vuole molti di più. L'overlay
ha 16KB tutti suoi. Vedi `memory/code_overlay_architecture.md`.

Validato in slice51: l'audio continua a suonare mentre un overlay gira, quindi
la musica di battaglia non è un problema.

### La divisione delle responsabilità

**Nel banco fisso, come `svc_*`** — tutto ciò che serve anche fuori dalla
battaglia, e tutto ciò che sta sul percorso della NMI.

Superficie effettiva dopo slice52 (dichiarata in `src/svc_api.h`, un solo
posto per entrambe le parti, così le firme non possono divergere in silenzio):

```
svc_vwrite / svc_vfill / svc_put_sprite16   primitive VDP
svc_wait_vblank
svc_joystick        joystick + tastierino P1 (NON joystick() di libreria)
svc_battle_load_gfx l'unica che cambia banco: va a prendere le CHR nel banco 2
                    e rimette il banco 20 prima di tornare
```

Il testo (stringhe, cifre, righe piene) l'overlay se lo costruisce da solo
sopra `svc_vwrite`/`svc_vfill`: nel banco 20 lo spazio abbonda, nella finestra
fissa no. Il RNG resta nel banco fisso — è condiviso con l'encounter in
overworld e la sua sequenza è parte della parity — ma finora l'overlay non ne
ha bisogno, quindi la `svc_rng` non è ancora nata.

**Trappola scoperta in slice52: anche la rodata della LIBRERIA è a rischio.**
`joystick(3)` di z88dk decodifica il tastierino con una tabella in
`SECTION rodata_clib`, che il linker piazza a `$E890` — dentro la finestra
commutabile. Chiamata sotto l'overlay restituiva byte del banco 20 come codici
tasto. Rimpiazzata da `src/joy.asm`, che tiene codice **e** tabella in
`SECTION code_user`, cioè nella finestra fissa. La regola «le `svc_` non
toccano rodata del banco 0» va estesa: vale anche per la rodata che le
funzioni di libreria si portano dietro.

**Nell'overlay** — tutto il resto: formule di danno, IA nemica, risoluzione
del round, magie, ricompense.

**Vincolo da non violare:** una `svc_*` non deve mai toccare rodata del banco 0,
che è invisibile mentre l'overlay è mappato. Solo VDP, RAM e argomenti.

### Stato condiviso: RAM SGM

La RAM SGM (`$2000-$7FFF`) **non dipende dal banco**, quindi è il canale
naturale fra slice e overlay. Mappa attuale:

| Zona | Uso |
|---|---|
| `$2000-$5FFF` | buffer celle (`world_cells`), usato dall'espansione città |
| `$6C00-$6FFF` | BSS degli overlay (`overlay_crt0.asm`) |
| `$7000+` | BSS della slice principale |
| `$7FFE` | stack |

Il blocco di stato battaglia sta a **`$6000`**, dentro la zona libera
`$6000-$6BFF`. Struct `battle_state_t` in `src/battle_state.h`, inclusa da
entrambe le parti (64 byte: formazione, dominio, classi, nomi, HP/HPMAX,
colori accento, turno, comando, round, risultato). Il campo `magic` è la prova
che il canale ha funzionato: se l'overlay non lo riconosce stampa
`BAD BATTLE STATE AT 6000` invece di disegnare una schermata costruita su
valori a caso. Serve anche alla validazione automatica — `mame_drive_battle.lua`
riconosce l'ingresso in battaglia leggendo quel magic in RAM, non guardando lo
schermo. Non passare puntatori a rodata.

## Ordine delle slice

Ogni riga è una slice verificabile da sola. L'ordine è scelto perché ognuna
produce qualcosa di visibile, invece di accumulare motore invisibile.

1. ~~**ovl_battle scheletro**~~ — **FATTA in slice52 (2026-07-26).** La
   schermata è identica; è cambiato dove gira. Misure: la finestra fissa passa
   da **1720 a 4509 byte liberi**, l'overlay occupa **5667 dei 16384** byte del
   banco 20. Validata in MAME senza intervento umano
   (`tools/mame_drive_battle.lua`): ingresso in battaglia, cursore comandi,
   salto al CHR col tastierino, conferma comando, fuga e ritorno in overworld.
2. ~~**Stat reali**~~ — **FATTA in slice53 (2026-07-26).** Il gruppo vive in
   `src/party_state.h` (RAM SGM `$6100`, layout fedele a `ch_stats` di
   `variables.inc:367`) e viene inizializzato da `party_init_from_classes()`,
   che replica `NewGame_LoadStartingStats` (`bank_0F.asm:1811`) — inclusi i due
   MP di primo livello a mago rosso/bianco/nero, che sul NES stanno in codice e
   non nella tabella. Verificato in RAM: 35/30/28/25 HP per FT/TH/WM/BM contro
   i `{35,28,22,22}` inventati, di cui **tre su quattro erano sbagliati**.
   La battaglia non copia più niente: legge `PARTY` direttamente, perché la RAM
   SGM è visibile da ogni banco.
   **A schermo restano solo nome e HP**, come sul NES. Un primo giro mostrava
   anche forza/agilità e una riga `MP n`: sbagliato per parità (le statistiche
   in FF1 si vedono solo nel menu, le cariche di magia nel sottomenu magia) e
   soprattutto **fuorviante**, perché in FF1 non esistono MP come serbatoio
   unico — sono cariche per livello di magia, e un numero solo le rappresenta
   male. Le formule del turno fisico si controllano con la sonda in RAM di
   `tools/mame_drive_battle.lua`, non stampando a schermo numeri che il gioco
   originale non mostra.
   `class_stats.h` NON è finito in un banco: sono 96 byte letti una volta sola,
   e un banco costa 16KB di ROM più un header di simboli. Sta nella rodata
   della slice e si legge col banco 0 mappato — `party_init_from_classes()`
   viene chiamata subito dopo `mc_select_bank(0)`, non durante la selezione dei
   personaggi (là è mappato il banco 1 per il Prelude, e si leggerebbero le sue
   note come punti forza).
3. **enemy_data in banco + nemici veri** — nomi, HP, difesa, numero di
   attacchi della formazione estratta. La schermata smette di essere finta.
4. ~~**Turno fisico**~~ — **FATTA in slice57 (2026-07-28)**, lato giocatore.
   Selezione del bersaglio col tastierino, guard `chr_chosen[4]` (il round
   parte quando tutti i vivi hanno scelto — il salto col tastierino rompe
   l'ordine lineare), formula del danno da `DoPhysicalAttack`, colpo a vuoto,
   morte del nemico, vittoria vera. Il gancio provvisorio `*` è sparito.
   L'unica deviazione dal NES è il **fix #2** del digest AstralEsper: niente
   troncamento a 255 fra la somma del tiro e la sottrazione dell'evasione. In C
   viene naturale — il bug del NES nasceva dall'aritmetica a 8 bit, e
   riprodurlo richiederebbe di *aggiungere* codice.
   Il fix #1 (critico dal byte dell'arma, non dal suo indice) non è ancora
   osservabile: in FF1 si parte disarmati e arma 0 dà critico 0 in entrambe le
   letture. Validata in MAME: 5 IMP uccisi in 5 round, `RESULT=2`, EXP e GP
   assegnati. Vedi `memory/slice57_physical_turn.md`.
   **Il danno basso non è un difetto**: senza equipaggiamento il Fighter fa 10
   e i maghi 1-2, ed è FF1 — le armi si comprano a Coneria.
5. ~~**IA nemica + ordine di iniziativa**~~ — **FATTA in slice59 (2026-07-28).**
   Il round non è più del solo gruppo: 13 caselle (9 slot nemico + 4
   personaggi) mescolate come `DoBattleRound` (`bank_0C.asm:3199`), i nemici
   colpiscono, i personaggi muoiono, il gruppo può cadere.
   Costo nella finestra fissa: **zero byte** — sta tutto nell'overlay, che
   passa da 4535 a 1595 liberi.
   Dentro: distribuzione **frontale** del bersaglio (4/8 al primo, 2/8, 1/8,
   1/8 — la ragione per cui in FF1 il Fighter sta in cima), formula del colpo
   dal lato nemico, `FlashCharacterSprite`, fuga per **morale** bassa con
   EXP/oro tolti dal bottino, e la sconfitta.
   Resta fuori il ramo di `Enemy_DoAi` che sceglie magia e attacchi speciali:
   finisce sempre in `Enemy_DoMagicEffect`, cioè dentro il motore della magia.
   Vedi `memory/slice59_enemy_ai.md`.
6. ~~**EXP/GP e passaggio di livello**~~ — **FATTA in slice54.** Curva EXP e
   dati di livello byte-exact da `bank_0B` (`tools/extract_levelup_data.ps1` →
   `src/data/levelup_data.h`), nel **banco 11** `btldata_bank.c`, che da qui in
   poi ospita tutte le tabelle di regole consultate mentre l'overlay è mappato.
   `svc_award_exp()` divide gli EXP fra i superstiti (l'oro no, minimo 1 a
   testa), applica e fa salire di livello; ingresso e uscita via `BST`.
   Include il **fix multi-livello** deciso nel digest AstralEsper: sul NES si
   sale di un livello solo per battaglia, qui di tutti quelli che gli EXP
   consentono.
   Due cose da sapere prima di toccare il resto del motore:
   **(a)** il RNG di battaglia è ora **separato** da `battle_step_rng`, la cui
   sequenza è parte della parity dell'encounter — ma è un segnaposto, va
   sostituito col `BattleRNG` del NES quando arriva il turno fisico;
   **(b)** `ff1_rng_lut` è copiata in RAM (`rng_lut_cache`) perché era rodata,
   quindi illeggibile sotto qualunque banco diverso dallo 0.
   Resta fuori `LvlUp_AdjustBBSubStats` (danno e assorbimento del monaco a mani
   nude), lasciata non implementata invece che indovinata.
7. **Magia** — lista incantesimi, cariche, effetti base, e i fix ai bug NES già
   decisi in `memory/spell_bugs_ff1nes_to_fix.md`.
   **Attenzione al modello:** in FF1 non ci sono MP come serbatoio unico. Ci
   sono **8 livelli di magia, ognuno con le sue cariche** (`curmp[8]`/`maxmp[8]`
   in `party_state.h`, come `ch_curmp`/`ch_maxmp` sul NES). Il sottomenu della
   magia è il posto dove si vedono, un livello per riga — non un totale.
   A nuova partita mago rosso/bianco/nero partono con 2 cariche di livello 1 e
   zero su tutto il resto.
8. **Fuga + musica** — **FATTA in slice52.** La fuga c'era già dalla scaffold.
   `sng50` vive nel **banco 10** (`src/song_bank.c`) e suona mentre l'overlay
   gira nel banco 20 — la NMI salta fra i due a ogni frame.
   `init_bank1_song` è diventata `init_bank_song(bank, ...)`.
   **Sequenza di vittoria completa**: `sng53` + animazione di esultanza
   (`run_victory` in `ovl_battle.c`), che ricalca `PlayFanfareAndCheer`
   (`bank_0C.asm:2435`): 128 frame alternando esultanza e posa in piedi ogni
   16, poi posa naturale e riquadro di vittoria.
   Manca solo il **riquadro delle ricompense** (EXP/GP), che dipende dalla
   slice 6.
   **Gancio provvisorio da rimuovere:** il tasto `*` del tastierino finge una
   vittoria, perché senza combattimento la sequenza non avrebbe modo di
   partire. Sparisce quando la risoluzione del round sa far morire i nemici;
   la chiamata a `run_victory` resta dov'è.

## Debito già noto da rispettare

- **Guardia di inizio round** (`memory/battle_round_logic_todo.md`): con il
  tastierino si può saltare da un personaggio all'altro in ordine libero, quindi
  serve `chr_action_chosen[4]` e il round si risolve solo quando tutti e quattro
  hanno scelto. Non assumere l'ordine lineare della scaffold.
- **Quirk da preservare** (`memory/ff1_preserved_quirks.md`) contro
  **bug da correggere** (`memory/ff1_engine_intent_priorities.md`): sono due
  liste distinte, vanno consultate entrambe prima di scrivere una formula.

## Da leggere all'inizio della sessione

1. `memory/ff1_engine_intent_priorities.md` — i 15 fix decisi
2. `memory/spell_bugs_ff1nes_to_fix.md` — magia
3. `memory/battle_round_logic_todo.md` — la guardia di round
4. `src/data/enemy_data.h` e `class_stats.h` — formati
5. `src/slice49.c`, sezione battaglia — la scaffold da travasare
6. `docs/Coleco_improvements.md` — da aggiornare a ogni scelta non-parity

## Comando di build

```ps1
.\tools\build_all.ps1 -Slice slice52 -Overlays 'ovl_battle:20' -Run
```

## Validazione automatica

```ps1
mame coleco -exp sgm -cart build\slice52_mc512.rom -rompath mame_roms `
    -window -nofilter -skip_gameinfo -sound none -nothrottle `
    -seconds_to_run 400 -autoboot_script tools\mame_drive_battle.lua `
    -snapshot_directory build\snap_slice52
```

Due trappole nello script Lua, entrambe già pagate:

- **I campi input vanno cercati per porta**, non per nome. Nel driver coleco
  `P1 Button 1` esiste sia in `:STD_JOY1` sia in `:DRIV_PEDAL1`, e
  `P1 Down`/`P1 Right` sia in `:STD_JOY1` sia in `:SAC_JOY1`. Cercando per solo
  nome, con `pairs()` che ha ordine imprevedibile, metà dei comandi finiva su
  un controller che la ROM non legge — e sembrava un bug del gioco.
- **I due fire sono invertiti rispetto ai nomi**: MAME `:STD_JOY1 :: P1 Button 1`
  è `MOVE_FIRE2` per z88dk (letto in modo joystick), MAME
  `:STD_KEYPAD1 :: P1 Button 2` è `MOVE_FIRE1` (letto in modo tastierino).
