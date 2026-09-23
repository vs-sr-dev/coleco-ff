# Roadmap: one ROM, power-on to the bridge

**Goal.** A single release ROM, built with `build_all.ps1` and no test
defines, in which the first arc of Final Fantasy can be played from power-on
to the bridge scene. It has to be proved by one scripted MAME run that plays
it end to end, with no seeded party and no seeded flags.

**Where slice78 stands** (audited 2026-09-23). All of the quest logic exists:
legend → class select → Coneria → castle → Temple of Fiends → Garland →
Princess → Lute → King → bridge → title card. What is missing is the rest of
the game around it, and one playthrough that goes from start to finish:

- Only 2 of the 13 regression runs use the real ROM. The quest run seeds four
  300-HP fighters with random encounters switched off, and the bridge run
  seeds the bridge flag.
- `mame_drive_intro/battle/collision.lua` exist but are not in the suite.
- The fixed bank has **123 bytes free**. Chests, Game Over and every later
  map feature touch `town_tick`, which lives in the fixed bank.
- Free MegaCart banks: **7, 28, 29, 30**.

Estimates are in working sessions.

---

## M1: the town-loop overlay (prerequisite, ~1 session)

Move the standard-map loop (`town_tick`, `enter_town`, the map-bank copies)
out of the fixed bank into an overlay in bank 28, behind two new `svc_`
calls: map bank → VRAM, and map bank → RAM. This frees roughly 2.8-3.2 KB.
`TD` is already in RAM, which makes it the same kind of move as slice62 and
slice72.

*Done when* the 13 runs pass and the fixed bank has more than 2.5 KB free.

## M2: the boss path cannot be cheated (~1 session)

- **RUN**: implement the NES escape roll, and respect `BST.no_run`. Today RUN
  always works and FIRE2 escapes at any point, so Garland can be fled.
- **Why this matters for the quest**: `Talk_Garland` hides Garland *before*
  the fight, and the NES does the same (`bank_0E.asm:1059`). That is only
  safe because on the NES you cannot flee from him and losing is Game Over.
  Once RUN and Game Over are fixed, the order is correct again, and nothing
  in the quest code needs to change.
- **Game Over**: a party wipe goes to a Game Over screen with sng52 and then
  back to the legend. Today the party is healed in full and put back on the
  map.
- **DRINK / ITEM in battle**: HEAL and PURE potions (Coneria sells both).
  Today they print "NOT YET".

*Done when* a new run `garland` fights Garland with an unseeded level-1 party
and asserts that RUN is refused and that a loss ends in Game Over.

## M3: treasure chests (~1 session)

Twelve chests along the path: Castle 1F (ids 1-6, row y=11) and Temple of
Fiends (ids 7-12). This needs `TP_SPEC_TREASURE`, the `GMFLG_TCOPEN` bit
(already in `world_state.h`), the item or gold going into the bag, the NES
message, the full-bag case, and the chest jingle (track `$58`, one more line
in `import_assets.ps1`).

*Done when* a `chests` run opens all 12 chests and checks the bag and the
flags, including a second visit that finds each chest empty.

## M4: naming and the rough edges of the opening (~0.5 session)

- **Name entry** after class select. A working screen already exists in
  slice22b. Port it into the intro overlay, where bank 21 has about 10 KB free.
- Make CONTINUE on the boot menu do something honest, or hide it, until
  saving exists (see decision D1).
- Replace the `TPxx` debug text shown at unported entrances (Pravoka and every
  other one) with the NES behaviour for a closed door, or with a clean
  "end of demo" message.

## M5: the release slice and the end-to-end run (~1-2 sessions)

- `slice79` = the release candidate. `build_all.ps1` defaults to it.
- **`mame_drive_demo.lua`**, the run that defines done. It plays power-on →
  legend → class select → naming → shopping → the King → the overworld with
  real random encounters → the Temple → Garland → the Princess → the King →
  the bridge → the title card, on the release ROM. Battles are driven from
  RAM, not on a timer (see the notes on closed-loop driving). The run must
  survive the encounter RNG, so either the party grinds to a safe level
  first, or the run records its seed and replays it.
- Add `intro`, `battle`, `collision` and `demo` to `run_regressions.ps1`.
- **Make the bridge run closed-loop.** It skips the intro with blind presses
  until frame 2200 and starts checking at frame 2350. On 2026-09-23 it failed
  once in 7 executions of the same code: at the first check the tiles were
  blank (32), not the bridge. It could not be reproduced in 6 reruns. Start
  its plan on a RAM condition (overworld drawn), as the other runs do, and
  keep the full MAME log of a failed run instead of only the failure lines.
- Decide what happens after the title card: return to the overworld (as
  now), or end the demo.

*Done when* `demo` passes on the release ROM, the whole suite is green, and
the same ROM has been played by hand on **CoolCV and MAME** (cross-emulator,
per the project rule that MAME wins when the two disagree).

## M6: battle animations (~1-2 sessions)

Weapon swings (11 icons), spell casts (8), explosions (3). The constraint is
the OAM: 32 sprites and 4 per scanline, and the battle already uses sprites
for the party. It is not a tile problem. Bank 20 has 1,135 bytes free, so the
effect code probably goes into bank 29 or next to the `ovl_btlmagic`
routines. The boss artwork for the Fiends and Chaos ("BOSS GFX TBD") is
outside this arc and stays out.

## M7: polish (~1 session)

The menu theme (sng4F); the fanfare, which is cut 4 frames early; the
overworld theme, which restarts after the menu; SELL in shops; the
Talk_* routines that the four demo maps still answer with their first line;
monster-vs-monster confusion; stale comments (`ovl_shop.c`, `song_bank.c`).

---

## Decisions that are the author's to make

- **D1, saving.** The NES saves at the inn to battery RAM. The SGM has no
  non-volatile memory. The options are a password (`Coleco_improvements.md`
  §4), a cart with SRAM (the MegaCart has none), or no save for a
  first-arc demo. This blocks CONTINUE.
- **D2, where the demo ends.** Stop at the title card, or leave the first
  continent open to walk around after it.
- **D3, M6 before or after the release.** The arc is playable without
  animations. Recommendation: release after M5, then do M6.

## Proposed order

**M1 → M2 → M3 → M4 → M5** is the path to the single ROM, about 4-6 sessions.
M6 and M7 follow. M1 comes first because M2 and M3 both need space in the
fixed bank that does not exist today.
