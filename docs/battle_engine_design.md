# Battle engine — plan of attack (block B)

Handoff document written at the end of session 12, while the bank
architecture was still fresh in mind. Its purpose is to let the next session
start from a plan instead of from an exploration.

## Starting point

What already exists and works:

- **NES-parity battle screen** (slice24-35): the 4 characters' sprites
  in color, stats strip, command box, monster area, backdrop band.
  Lives in `slice49.c`, functions `render_battle_screen` / `battle_tick`.
- **Byte-parity encounters**: `compute_domain` + `get_battle_formation` +
  `battle_step_rng` produce the same formation the NES would give.
  Confirmed working by the user in session 12.
- **Data imported and never used**, in `src/data/`: `enemy_data.h` (3713 bytes),
  `class_stats.h` (96), `magic_data.h` (832), `weapon_data.h` (406),
  `armor_data.h` (240), `shop_data.h` (935).

What is missing is **all of the logic**: `battle_tick` is an interface
scaffold. FIRE1 prints "CHR1 > FIGHT" and moves on to the next character. No
damage, no enemy that acts, no victory.

## Where the code goes

The engine goes in an **overlay** (`ovl_battle.c`, bank 20), not in the fixed bank:
only 1720 bytes are left free there and the engine wants many more. The overlay
has 16KB all to itself. See `memory/code_overlay_architecture.md`.

Validated in slice51: audio keeps playing while an overlay runs, so
battle music is not a problem.

### Division of responsibilities

**In the fixed bank, as `svc_*`** — everything that is also needed outside
battle, and everything that sits on the NMI path.

Actual surface after slice52 (declared in `src/svc_api.h`, a single
place for both sides, so the signatures cannot silently diverge):

```
svc_vwrite / svc_vfill / svc_put_sprite16   VDP primitives
svc_wait_vblank
svc_joystick        joystick + P1 keypad (NOT the library joystick())
svc_battle_load_gfx the only one that switches bank: fetches the CHR from bank 2
                    and restores bank 20 before returning
```

The overlay builds text (strings, digits, filled rows) by itself on top of
`svc_vwrite`/`svc_vfill`: in bank 20 there is plenty of room, in the fixed
bank there isn't. The RNG stays in the fixed bank — it is shared with the
overworld encounter and its sequence is part of the parity — but so far the
overlay hasn't needed it, so `svc_rng` doesn't exist yet.

**Trap discovered in slice52: the LIBRARY's rodata is at risk too.**
z88dk's `joystick(3)` decodes the keypad with a table in
`SECTION rodata_clib`, which the linker places at `$E890` — inside the
switchable window. Called under the overlay, it returned bytes from bank 20 as
key codes. Replaced by `src/joy.asm`, which keeps code **and** table in
`SECTION code_user`, i.e. in the fixed bank. The rule "`svc_` functions don't
touch bank 0 rodata" must be extended: it also applies to the rodata that
library functions bring along with them.

**In the overlay** — everything else: damage formulas, enemy AI, round
resolution, magic, rewards.

**Constraint not to be violated:** an `svc_*` must never touch bank 0 rodata,
which is invisible while the overlay is mapped. Only VDP, RAM and arguments.

### Shared state: SGM RAM

SGM RAM (`$2000-$7FFF`) **does not depend on the bank**, so it is the
natural channel between slice and overlay. Current map:

| Zone | Use |
|---|---|
| `$2000-$5FFF` | cell buffer (`world_cells`), used by the town expansion |
| `$6C00-$6FFF` | overlay BSS (`overlay_crt0.asm`) |
| `$7000+` | main slice BSS |
| `$7FFE` | stack |

The battle state block sits at **`$6000`**, inside the free zone
`$6000-$6BFF`. Struct `battle_state_t` in `src/battle_state.h`, included by
both sides (64 bytes: formation, domain, classes, names, HP/HPMAX,
accent colors, turn, command, round, result). The `magic` field is the proof
that the channel worked: if the overlay doesn't recognize it, it prints
`BAD BATTLE STATE AT 6000` instead of drawing a screen built on
random values. It also serves automated validation — `mame_drive_battle.lua`
recognizes entering battle by reading that magic in RAM, not by looking at the
screen. Do not pass pointers to rodata.

## Slice order

Each line is a slice that can be verified on its own. The order is chosen so
that each one produces something visible, instead of piling up invisible engine.

1. ~~**ovl_battle skeleton**~~ — **DONE in slice52 (2026-07-26).** The
   screen is identical; what changed is where it runs. Measurements: the fixed
   bank goes from **1720 to 4509 free bytes**, the overlay takes **5667 of the
   16384** bytes of bank 20. Validated in MAME with no human intervention
   (`tools/mame_drive_battle.lua`): entering battle, command cursor,
   jumping to a CHR with the keypad, command confirmation, escape and return to
   the overworld.
2. ~~**Real stats**~~ — **DONE in slice53 (2026-07-26).** The party lives in
   `src/party_state.h` (SGM RAM `$6100`, layout faithful to `ch_stats` from
   `variables.inc:367`) and is initialized by `party_init_from_classes()`,
   which replicates `NewGame_LoadStartingStats` (`bank_0F.asm:1811`) — including
   the two level-1 MP of the red/white/black mage, which on the NES live in code
   and not in the table. Verified in RAM: 35/30/28/25 HP for FT/TH/WM/BM versus
   the made-up `{35,28,22,22}`, of which **three out of four were wrong**.
   The battle no longer copies anything: it reads `PARTY` directly, because SGM
   RAM is visible from every bank.
   **Only name and HP remain on screen**, as on the NES. A first pass also
   showed strength/agility and an `MP n` row: wrong for parity (in FF1 stats
   are only visible in the menu, magic charges in the magic submenu) and
   above all **misleading**, because FF1 has no MP as a single pool
   — they are charges per spell level, and a single number represents them
   badly. The physical-turn formulas are checked with the RAM probe in
   `tools/mame_drive_battle.lua`, not by printing on screen numbers the
   original game doesn't show.
   `class_stats.h` did NOT end up in a bank: it's 96 bytes read only once,
   and a bank costs 16KB of ROM plus a symbol header. It sits in the slice's
   rodata and is read with bank 0 mapped — `party_init_from_classes()`
   is called right after `mc_select_bank(0)`, not during character
   selection (bank 1 is mapped there for the Prelude, and its notes would be
   read as strength points).
3. **enemy_data in a bank + real enemies** — names, HP, defense, number of
   attacks of the extracted formation. The screen stops being fake.
4. ~~**Physical turn**~~ — **DONE in slice57 (2026-07-28)**, player side.
   Target selection with the keypad, `chr_chosen[4]` guard (the round
   starts when all living characters have chosen — jumping with the keypad breaks
   the linear order), damage formula from `DoPhysicalAttack`, misses,
   enemy death, real victory. The temporary `*` hook is gone.
   The only deviation from the NES is **fix #2** from the AstralEsper digest: no
   truncation to 255 between the roll sum and the evasion subtraction. In C
   it comes naturally — the NES bug came from 8-bit arithmetic, and
   reproducing it would require *adding* code.
   Fix #1 (critical from the weapon's byte, not from its index) is not yet
   observable: in FF1 you start unarmed and weapon 0 gives critical 0 under both
   readings. Validated in MAME: 5 IMPs killed in 5 rounds, `RESULT=2`, EXP and GP
   awarded. See `memory/slice57_physical_turn.md`.
   **Low damage is not a defect**: without equipment the Fighter does 10
   and the mages 1-2, and that's FF1 — weapons are bought in Coneria.
5. ~~**Enemy AI + initiative order**~~ — **DONE in slice59 (2026-07-28).**
   The round no longer belongs to the party alone: 13 slots (9 enemy slots + 4
   characters) shuffled like `DoBattleRound` (`bank_0C.asm:3199`), the enemies
   hit, the characters die, the party can fall.
   Cost in the fixed bank: **zero bytes** — it all lives in the overlay, which
   goes from 4535 to 1595 free.
   Inside: **front-weighted** target distribution (4/8 to the first, 2/8, 1/8,
   1/8 — the reason why in FF1 the Fighter goes on top), hit formula
   from the enemy side, `FlashCharacterSprite`, fleeing on low **morale** with
   EXP/gold removed from the loot, and defeat.
   Left out is the branch of `Enemy_DoAi` that picks magic and special attacks:
   it always ends up in `Enemy_DoMagicEffect`, i.e. inside the magic engine.
   See `memory/slice59_enemy_ai.md`.
6. ~~**EXP/GP and level up**~~ — **DONE in slice54.** EXP curve and
   level data byte-exact from `bank_0B` (`tools/extract_levelup_data.ps1` →
   `src/data/levelup_data.h`), in **bank 11** `btldata_bank.c`, which from here
   on hosts all the rule tables consulted while the overlay is mapped.
   `svc_award_exp()` splits the EXP among the survivors (not the gold, minimum 1
   each), applies it and levels up; input and output via `BST`.
   It includes the **multi-level fix** decided in the AstralEsper digest: on the NES
   you only gain one level per battle, here as many as the EXP
   allow.
   Two things to know before touching the rest of the engine:
   **(a)** the battle RNG is now **separate** from `battle_step_rng`, whose
   sequence is part of the encounter parity — but it's a placeholder, to be
   replaced with the NES `BattleRNG` when the physical turn arrives;
   **(b)** `ff1_rng_lut` is copied into RAM (`rng_lut_cache`) because it was rodata,
   hence unreadable under any bank other than 0.
   Left out is `LvlUp_AdjustBBSubStats` (bare-handed damage and absorb for the
   monk), left unimplemented rather than guessed.
7. **Magic** — spell list, charges, basic effects, and the fixes to the NES bugs
   already decided in `memory/spell_bugs_ff1nes_to_fix.md`.
   **Watch the model:** in FF1 there are no MP as a single pool. There
   are **8 spell levels, each with its own charges** (`curmp[8]`/`maxmp[8]`
   in `party_state.h`, like `ch_curmp`/`ch_maxmp` on the NES). The magic
   submenu is where they are shown, one level per row — not a total.
   On a new game the red/white/black mage start with 2 level-1 charges and
   zero on everything else.
8. **Escape + music** — **DONE in slice52.** Escape was already there from the scaffold.
   `sng50` lives in **bank 10** (`src/song_bank.c`) and plays while the overlay
   runs in bank 20 — the NMI jumps between the two every frame.
   `init_bank1_song` became `init_bank_song(bank, ...)`.
   **Full victory sequence**: `sng53` + cheer animation
   (`run_victory` in `ovl_battle.c`), which mirrors `PlayFanfareAndCheer`
   (`bank_0C.asm:2435`): 128 frames alternating cheer and standing pose every
   16, then natural pose and victory box.
   Only the **rewards box** (EXP/GP) is missing, which depends on
   slice 6.
   **Temporary hook to remove:** the keypad's `*` key fakes a
   victory, because without combat the sequence would have no way to
   start. It goes away when round resolution can kill enemies;
   the call to `run_victory` stays where it is.

## Known debt to honor

- **Round start guard** (`memory/battle_round_logic_todo.md`): with the
  keypad you can jump from one character to another in any order, so
  `chr_action_chosen[4]` is needed and the round resolves only when all four
  have chosen. Do not assume the scaffold's linear order.
- **Quirks to preserve** (`memory/ff1_preserved_quirks.md`) versus
  **bugs to fix** (`memory/ff1_engine_intent_priorities.md`): they are two
  distinct lists, and both must be checked before writing a formula.

## To read at the start of the session

1. `memory/ff1_engine_intent_priorities.md` — the 15 decided fixes
2. `memory/spell_bugs_ff1nes_to_fix.md` — magic
3. `memory/battle_round_logic_todo.md` — the round guard
4. `src/data/enemy_data.h` and `class_stats.h` — formats
5. `src/slice49.c`, battle section — the scaffold to port over
6. `docs/Coleco_improvements.md` — to be updated at every non-parity choice

## Build command

```ps1
.\tools\build_all.ps1 -Slice slice52 -Overlays 'ovl_battle:20' -Run
```

## Automated validation

```ps1
mame coleco -exp sgm -cart build\slice52_mc512.rom -rompath mame_roms `
    -window -nofilter -skip_gameinfo -sound none -nothrottle `
    -seconds_to_run 400 -autoboot_script tools\mame_drive_battle.lua `
    -snapshot_directory build\snap_slice52
```

Two traps in the Lua script, both already paid for:

- **Input fields must be looked up by port**, not by name. In the coleco driver
  `P1 Button 1` exists both in `:STD_JOY1` and in `:DRIV_PEDAL1`, and
  `P1 Down`/`P1 Right` both in `:STD_JOY1` and in `:SAC_JOY1`. Looking up by
  name only, with `pairs()` having unpredictable order, half the commands ended up on
  a controller the ROM doesn't read — and it looked like a game bug.
- **The two fire buttons are swapped relative to their names**: MAME `:STD_JOY1 :: P1 Button 1`
  is `MOVE_FIRE2` for z88dk (read in joystick mode), MAME
  `:STD_KEYPAD1 :: P1 Button 2` is `MOVE_FIRE1` (read in keypad mode).
