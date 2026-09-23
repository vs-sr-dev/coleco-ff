# Final Fantasy — Coleco Port Improvements vs NES Original

Catalog of the changes/improvements introduced relative to Final Fantasy NES (USA) in
the ColecoVision port. They live **alongside** NES parity for gameplay mechanics;
they are non-destructive additions that exploit Coleco hardware/UX or
fix objective ROM bugs.

Updated: 2026-05-08 (session 6).

---

## 1. UX / input

### 1.1 Numpad keypad as direct-select
- **What:** Keys `1`-`4` on the Coleco keypad jump directly to the corresponding
  CHR on the party / class-select / (in future) battle target screen.
- **Why:** The keypad is a Coleco hardware upgrade absent on the NES. Using it
  avoids cycling through the characters one at a time with the D-pad (slow).
  Functionally nothing changes: a battle round still starts once all four
  commands are in, and the game still starts once all four names are in,
  whatever the order. Consistent with `design_input.md`.
- **Status:** ✅ implemented in slice22b (class select); to be extended to battle
  command target select and the inventory menu.

### 1.2 `*` key as "confirm party"
- **What:** Dedicated `*` button on the keypad to confirm the party after class-select
  and proceed to game start. Distinct from keys 1-4 (CHR jump).
- **Why:** On NES the linear flow auto-advanced. With the 1-4 jump an
  explicit trigger is needed. `*` reserved for "commit/done", `#` free for future use
  (e.g. global cancel/back).
- **Status:** ✅ implemented in slice22b. Requires all 4 CHR named.

### 1.3 6-character CHR names (vs NES 4)
- **What:** Character name buffer increased from 4 → 6 chars.
- **Why:** On NES the limitation was a display/cart constraint (4-char box in the
  battle status). Coleco mode 2 has more cell space (14 col vs ~10 NES). Allows
  more descriptive names (e.g. "GANDLF" vs "GAND").
- **Cost:** +8 bytes of save state (4 CHR × 2 extra bytes) → ~+1 char in the final
  password. Negligible.
- **Status:** ✅ implemented in slice22b.

### 1.4 NES-parity flow + non-NES enhancements coexist
- **What:** The class-select flow follows NES parity (D-pad cycle, FIRE1 name,
  FIRE2 cycle backward) **+** Coleco add-ons (1-4 jump, * confirm).
- **Why:** A NES-faithful player can ignore the keypad and use only the joystick →
  experience identical to the NES. A Coleco-savvy player uses the keypad → faster UX.

### 1.5 The shop: buying EQUIPS
- **What:** when a weapon or armor is bought, if the class can wear it and the
  slot is free (only one weapon; one body armor, one shield, one helmet, one glove)
  it is **equipped immediately**. If the slot is taken it stays in the pack, with
  bit 7 clear, exactly as on the NES.
- **Why:** on the NES a purchase puts the item in the inventory, and to
  equip it you go through the MENU (`ReadjustEquipStats`). The menu doesn't exist here
  yet: without the automatic step, buying would not change **a single visible
  number** and the party would stay unarmed — meaning half the formulas of the
  physical turn would keep running on zeros.
- **The conditions are the NES ones**, not looser: `IsEquipLegal`
  (bank_0E.asm:9060) checks the class permission and one piece per type. What we
  do NOT do is "take off the other one": removing something the player has
  chosen to wear is not a purchase's job.
- **Reversible:** when the equipment menu arrives, it will be able to undo this —
  and at that point the choice itself can be reconsidered.
- **UNDOABLE SINCE slice74.** The equipment menu exists (§1.11): what the shop
  puts on can be taken off, handed to someone else, and thrown away. The
  deviation stays — buying equips — but as a convenience, not a sentence.
- **Status:** implemented in slice66 (weapons and armor). Validated in MAME,
  44 checks out of 44.

### 1.6 The class restriction is shown BEFORE buying
- **What:** on the "who gets it?" screen, the characters who cannot wear the
  highlighted entry are marked `NO`.
- **Why:** on the NES the restriction is only discovered from the menu, after paying: the
  sword bought for the mage sits in the pack doing nothing, and no
  screen ever says so. The information is already there (the permissions travel with the
  price list); showing it costs nothing and takes nothing away from someone who wants to buy
  anyway — the purchase stays allowed, as on the NES.
- **Status:** implemented in slice66.

### 1.6bis The magic shop says WHY not
- **What:** in each character's row the magic shop shows the
  level of the highlighted spell, how many spells of that level that
  character already knows (`2/3`), and one of three labels: `NO` (the class can't
  learn it), `KNOWN` (already knows it), `FULL` (the level's three slots are
  taken).
- **Why:** these are exactly the three refusals of `MagicShop_AssertLearn`, and on the
  NES they are discovered **one at a time and only by trying** — you pick the
  character, confirm, and only then does a window say no. The computation to
  know it beforehand is the same one the shop does anyway to decide: showing it
  adds no information to the game, it removes wasted attempts. The refusals
  all stay in place with their messages: whoever presses anyway sees
  the same answer as on the NES.
- **Parity note:** the cap of **three** spells per level, the choice among
  **eight**, and the fact that learning cannot be undone are NES-faithful and
  untouched — they are the game.
- **Status:** implemented in slice67.

### 1.6ter Magic submenu: levels via the keypad
- **What:** in the battle magic submenu, keys `1`-`8` jump
  directly to the level, and the page (L1-4 / L5-8) **follows** the chosen
  level instead of being a separate command.
- **Why:** on the NES the page is changed with a dedicated button because there's no
  other way. With eight levels and three slots, reaching a
  level 7 spell means counting cursor steps -- which is exactly the
  work the keypad exists to avoid (see 1.1). The directions
  keep working identically for those who prefer them.
- **Note:** the CHARGES of each level (`n/m`) are shown here and only here, as
  on the NES: the battle strip shows name and HP and nothing else. It's not a
  gap -- in FF1 "MP" isn't a pool but eight counters, and a
  single number under the HP would represent them poorly.
- **Status:** implemented in slice68.

### 1.7 Keypad in the shop
- **What:** keys `1`-`5` choose the price-list entry, `1`-`4` the
  character, without going through the cursor.
- **Why:** same reason as 1.1 — the keypad is hardware the NES didn't
  have. The D-pad keeps working identically for those who ignore it.
- **Status:** implemented in slice66.

### 1.8 The item shop shows HOW MANY you already have
- **What:** next to each price-list entry, the `IN PACK` column with the
  quantity already in the pack. On the NES that number is only visible by leaving the shop
  and opening the menu.
- **Why:** the only question you ask in front of a potion shop is
  "how many do I already have". Making it cost two screens is friction with no gameplay
  content. Plus it makes the purchase VISIBLE: the quantity going from 0 to 1 is
  the confirmation that the shop worked.
- **Status:** implemented in slice71.

### 1.9 The menu on FIRE2, and commands via the keypad
- **What:** FIRE2 opens the menu from the overworld and from town; keys `1`-`5`
  choose ITEM/MAGIC/WEAPON/ARMOR/STATUS and `1`-`4` the character.
- **Why:** on the NES the menu opens with START, which doesn't exist on the Coleco.
  FIRE2 was free in both game loops. The keypad is the usual
  shortcut from 1.1: on the NES getting to STATUS costs four presses.
- **Status:** implemented in slice73.

### 1.10 The stats screen shows EVERYTHING, INT included
- **What:** a single screen with the five base stats, the five
  derived ones beside them, the eight magic counters, EXP, how much is LEFT to the next
  level, and the equipment with an asterisk on what is equipped.
- **Why:** on the NES the same information is scattered across two screens, and
  `ch_exptonext` is a field the game computes *and never uses*. Here INT has
  stopped being a dead stat (§3.3): a stat nobody can
  read and a stat that doesn't exist look too much alike.
- **Parity note:** the **total** to reach would be the ROM's value; here
  the **difference** is shown, because the total alone forces you to do the
  subtraction in your head every time.
- **Status:** implemented in slice73.

### 1.11 WEAPON / ARMOR: the three modes on one key, and no blinking (slice74)
- **What:** the equipment grid shows all sixteen of the
  party's slots (like the NES), and the three modes **EQUIP / TRADE / DROP** are chosen with
  keypad `1`-`3`, without entering and leaving a submenu. The cursor always stays
  on the grid: the key decides what FIRE1 does.
- **Why:** on the NES the mode is a second level (`eq_modecurs`, A to
  enter, B to leave — `EnterEquipMenu`, bank_0E.asm:8845) because there are
  two buttons. With twelve extra keys that level is just a cost. It's the same
  shortcut as §1.1, §1.7 and §1.9.
- **What changes compared to the NES, concretely:** taking off a weapon to give it to
  someone else cost five presses on the NES (B, down, A, move, A); here it costs
  three.
- **No blinking:** the NES blinks the second TRADE cursor and the
  DROP confirmation one. Here the two cursors are **two different
  characters** (`>` where you are, `<` on what you picked up) and the confirmation is
  written out in words. It's not just readability: a screen position that counts
  as evidence must be **assertable** from VRAM (slice66 rule), and a
  character that is there every other frame is not.
- **The rest is NES-faithful**, including the two rules you notice while playing: a
  traded piece comes out **unequipped** on both sides (nobody asked about the new
  owner's permission), and **taking off** something never goes
  through the class check.
- **Status:** implemented in slice74. Validated in MAME, 64 checks out of 64.

### 1.12 MAGIC outside battle: three intent fixes (slice75)
- **CUR4 refuses those who can't be healed.** On the NES it doesn't check
  ailments — the disassembly itself says `BUGGED` (bank_0E.asm:6547):
  cast on a fallen or petrified character it fills their HP, and they stay
  fallen or petrified. The result is a seventh-level charge spent for
  nothing **with the screen showing the number gone up**, i.e. the worst
  kind of bug: the one that looks like it worked. Here it refuses like the whole
  CURE family, and the charge isn't consumed.
- **WARP and EXIT don't charge if there's nowhere to go.** On the NES the
  charge is consumed anyway (`DEC ch_magicdata` before the jump). Here the
  refusal comes before paying, as with every other menu refusal.
- **The roll no longer comes from the frame counter.** On the NES the amount
  healed is a masked `framecounter`, a stopgap that the disassembly comment
  declares as such ("make-shift pRNG", bank_0E.asm:6474) because outside
  battle the real generator isn't initialized. We have one
  (`svc_battle_rng`). **The ranges stay exactly the NES ones** — CURE
  16-31, CUR2 32-63, CUR3 64-127, HEAL 16-23, HEL2 32-47, HEL3 64-95: the only change
  is that the number no longer depends on WHEN you press the button, which on the NES
  can be exploited to always get the maximum heal.
- **Parity note, not a deviation:** from a town WARP and EXIT do the
  same thing (you return to the overworld at the entry coordinates), and it's the same
  on the NES — with a short teleport chain, WARP jumps into
  EXIT's code (bank_0E.asm:6719).
- **Status:** implemented in slice75. Validated in MAME, 60 checks out of 60.

---

### 1.13 Townspeople stand STILL (slice76)

**On the NES a town's townspeople wander.** Not here: they stand where the ROM
puts them and never move.

**It's not a matter of taste, it's the TMS9918.** The player's mapman is made
of **four overlapping sprites** (outline + two body colors +
skin tone), and the TMS shows **four per scanline**: a townsperson drawn
as a sprite would be the fifth and would vanish. And it would vanish exactly when you
look at them, because to talk to them you have to be next to them -- that is, on their
same scanlines.

Townspeople are therefore **background tiles**, and their four tiles contain
the terrain they stand on: moving them would mean rebaking them for every walkable
cell on the map.

**What changes in play, concretely:**
- a townsperson never gets in the way while you walk, and you never lose
  sight of one you were talking to. It's a loss of town liveliness and a
  gain in predictability;
- on the NES you PUSH a townsperson (`mapobj_pl`) and they move one cell.
  Here they **block**, like a wall. The same condition serves two purposes: it refuses
  the step, and "facing them" is the only way to talk to them.

Reversible only with a change of technique, not of a parameter.

### 1.14 The dialogue box covers the lower half, always (slice76)

On the NES the dialogue box opens in a position that depends on the
scroll. Here it's **fixed at rows 14-23**, below the player -- who is
pinned to cell (15,11) and 16 pixels tall, i.e. rows 11 and 12.

It's a consequence of discrete macrotile movement ([[movement-discrete-tile]]):
without fine scroll, "below the player" is always the same place, and a
box that moved would have nothing to adapt to. You always see
who you're talking to.

The text is **byte for byte FF1's**, unpacked from the ROM's DTE compression:
24 columns and up to 8 rows, which are the real sizes of the
game's dialogues (measured, and the extractor stops with an error if a text exceeds them).

Three charset fixes relative to the disassembly's table, all
verified against what the game actually shows:
- **$BE is an APOSTROPHE**, not a double quote: without the fix it
  reads `Lukahn"s` instead of `Lukahn's`;
- **$C3** (not in the table) is the ellipsis tile,
  which FF1 always uses in pairs: it becomes a period, so `$C3 $C3` gives `..`;
- **$FF** is the EMPTY tile, i.e. a space -- leaving it null would have
  shifted everything that follows to the left.

## 1bis. PACK deviations (slice71 + slice73)

### 1bis.1 The four orbs don't appear in the item list
- **What:** slots `$12-$15` exist in the inventory, but the ITEM screen
  skips them.
- **Why:** in the ROM their NAME IS EMPTY (seven spaces, `item_names.h`).
  Listing them would give four blank rows with a `1` on the right, which doesn't read
  as "you have an orb" but as a broken list. It's not a data gap:
  on the NES the orbs are shown in the main menu as four lit or
  unlit gems. **Declared debt:** the four gems, once the orbs can be
  obtained.
- **Status:** implemented in slice73.

### 1bis.2 HOUSE: magic charges ALWAYS come back
- **What:** the house restores 120 HP to everyone and refills all eight magic
  counters.
- **Why:** on the NES it does so only for those who SAVE the game — `MenuRecoverPartyMP`
  is called after `SaveGame`, inside the "has saved" branch (`bank_0E.asm:7095`,
  and the disassembler's comment says *"some would say this is BUGGED"*).
  Here there's no save yet, so there's no branch to hang
  the effect on: the house always does everything. It's a reading of intent, not a
  shortcut — when saving arrives, this entry must be re-read.
- **Status:** implemented in slice73.

### 1bis.3 SOFT brings you back up with ONE HP
- **What:** when stone is cured, if current HP was zero it becomes 1.
- **Why:** on the NES `CureOBAilment` just clears the bit, and a petrified character
  at zero HP comes back as a living one at zero HP — a state that doesn't exist anywhere else
  in the game (and that behaves in undefined ways at the first hit). One HP is the
  same rule the clinic uses to revive the fallen (`EnterShop_Clinic`).
- **Status:** implemented in slice73.

---

## 2. Audio

### 2.1 Bass line via AY-3-8910 SGM
- **What:** All songs use 4 voices (SN76489 SQ1+SQ2+NOISE + AY TRI/triangle-equivalent).
  On the NES there were 3 (SQ1/SQ2/TRI/NOISE → 4 but timing-shared).
- **Why:** The SGM adds the AY-3-8910 (3 extra voices). Better triangle/bass fidelity
  than the SN76489 alone. Decision: use the AY, since the SGM is already hard-required for RAM.
- **Status:** ✅ Prelude, Battle Theme, OW theme — all 24 songs via NMI hook.

---

## 3. Engine "intent" bug fixes (vs NES ROM bugs)

Full reference: `memory/ff1_engine_intent_priorities.md` + AstralEsper's
"Game Mechanics Guide" on GameFAQs.

Decision: the Coleco port fixes **all** ~50 cataloged combat/magic bugs of the NES
ROM. See `memory/spell_bugs_ff1nes_to_fix.md` and `ff1_engine_intent_priorities.md`
for details.

Top-priority examples:
- CRIT% reads the weapon `Crit` byte (no more Excalibur=39%, Masmune=40%)
- Hit% formula: no pre-evasion clamp
- TMPR/SABR/LOK2/HEL2/LOCK effect IDs corrected
- Weapon weakness bonus (+4 ATK, +40 BC) actually applied
- INT stat used (was ignored by the ROM)
- Status on miss → only on hit
- Multi-level-up loop (several levels in the same battle if EXP is enough)
- Running formula corrected (it read the status slot, not the runner's level)
- Regen tick (never executed on NES)
- Sleep wake-roll for enemies
- Bidirectional poison DoT (was PC-side only)

**Status:** TBD — implementation deferred to the battle/magic engine slice (post-slice24).

### 3.1 Group 2 palette in "mix" formations — FIXED (slice56)

- **What:** on NES, `PrepareEnemyFormation_Mix` (`bank_0B.asm:2576-2583`) does
  **six** `LSR` where five are needed, and for group 2 it therefore reads bit 6
  of the palette-assignment nibble — that is, group 1's — instead of
  bit 5. Our `decode_formation` uses the correct formula for all
  four groups.
- **Why it's a typo and not a behavior:** in the same routine groups
  0, 1 and 3 are right (`ROL`×2, `ROL`×3, `LSR`×4 → bits 7, 6, 4), and the
  twin routine for 9small/4large does group 2 with `ROL`×4, which correctly gives
  bit 5. There is no reading in which the author meant bit 6. Verified by
  recounting the shifts, not just from the disassembly comment.
- **How much it matters:** measured by `tools/census_mix_palette_bug.ps1`. Of the 29
  mix formations, three conditions are needed together (group 2 present, bit 5 ≠
  bit 6, palettes differing from each other): **only one** satisfies them. It's formation
  `44`, present in **only one domain out of 128** (`0x79`), where the **SeaTROLL**
  would come out with palette 19 (`$30/$2C/$13`, cyan) instead of 20
  (`$30/$22/$12`, blue).
- **Why fix rather than preserve:** a preserved quirk is something the
  game *does* and that someone seeks out on purpose — the Finger Point is an
  encounter table that players go out of their way to exploit. Here there's nothing to preserve:
  no strategy, no memory and no speedrun depends on the color of the
  SeaTROLL in one domain. The correct color is also more consistent (sea
  blue like the rest of the palette). And the cost asymmetry settles the
  question: our code is already correct, while preserving the bug
  would mean deliberately writing the wrong shift.
- **Status:** ✅ already this way since slice55's code, classified in slice56.

### 3.2 Class change — NES-faithful structure, two bugs fixed (decided session 16)

**The structure stays the NES one.** `DoClassChange` (`bank_0E.asm:1744-1766`)
writes a single byte per character, `ch_class += 6`, and nothing else: no
stats, no HP/MP, no recalculation. Promotion is a **permission
enabler** — equipment (`equip_bit = $800 >> class_id`,
`bank_0E.asm:9192`) and learnable spells (`lut_MagicPermisPtr`,
`bank_0E.asm:6081-6086`). The growth tables of the promoted classes point
**to the same bytes** as the base ones (`lut_LevelUpDataPtrs`, `bank_0B.asm:1207-1219`),
so stats grow identically before and after.

We don't adopt the growth differential introduced by the remakes (Origins, DoS,
PSP, Pixel Remaster). There, class change improves growth, and the optimal
strategy becomes promoting at the lowest possible level (L20) to maximize
the levels spent in the upper class. On the NES the moment of promotion is
irrelevant as far as stats go, and that's the version we're porting:
the remakes add balancing, and our mandate is to fix implementation
bugs, not to redesign the curves.

Two things, however, the NES gets wrong, and they fall into the "intent vs
implementation" category already decided for the other 15 fixes.

**(a) The Master loses magic defense by promoting.**

```
lut_LvlUpMagDefBonus:  3, 2, 4, 2, 2, 2,   3, 2, 1, 2, 2, 2
                      FT TH BB RM WM BM   KN NJ MA RW WW BW
```

`bank_0B.asm:1198`. It's the **only** entry that differs between the two halves of the
table — hit rate is identical for all six pairs, and every other class
keeps its own MagDef bonus. The BlackBelt has +4 per level, the Master
+1: promoting the monk makes him worse, and invisibly, because the damage
comes level after level and there's no screen that shows it. It's
fix #13 of `memory/ff1_engine_intent_priorities.md`, whose
cause we now know: it's not an abstract "BB/MA mismatch", it's the class change.

Fix: **the Master keeps +4**, just as all the other classes keep their
own. No class should regress by promoting.

**(b) The four "magic" promoted classes become undead.**

`bank_0C.asm:7702-7706` reads the player defender's category from the class
byte:

```asm
    LDY #ch_class - ch_stats        ; load category from OB
    LDA (btl_entityptr_obrom), Y    ; BUGGED - uses the class as the category
    STA btlmag_defender_category
```

`CATEGORY_UNDEAD` is `$08` (`Constants.inc:28`), tested in `bank_0C.asm:8374`.
Classes 8-11 — **Master, RedWizard, WhiteWizard, BlackWizard** — have bit
3 set and become valid targets for HARM/HARM2. No base class (0-5)
has it, so the defect **only appears after promotion**.

That it's a typo and not a design is stated by the disassembly comment
itself, but above all by the semantics: `ch_class` is an identifier, not
a category mask, and the coincidence between "fourth promoted class" and
"undead bit" has no sensible reading. Fix: the player defender's category
is **none** — characters don't belong to creature
categories.

- **Status:** decisions made; implementation when magic arrives
  (point 7 of `docs/battle_engine_design.md`) and promotion. Today there's
  neither HARM nor Bahamut yet.

### 3.3 INT — from dead stat to magic accuracy (decided session 16)

On the NES INT does **nothing**. `ch_int` (`variables.inc:379`) has only three
references in the whole ROM: the initial write (`bank_0F.asm:1846`), the
level-up loop that increments it (`bank_0B.asm:1014-1048`), and a read in
`bank_0E.asm:228` that only serves to **print** it on the status screen. It
isn't even copied into battle — `btl_chstats` has no INT field.

Yet it grows with carefully differentiated curves: the Black Mage gets the
increase guaranteed at **every** level 2→50, the Fighter in 14 levels out of 49. And the game
announces `"Int Up!"` at the end of battle. It was the mage's identity mark, and
it was left an empty shell.

**Where to hook it.** That isn't our call: the ROM leaves the slot wired and
empty. `PreparePlayerMagAttack` (`bank_0C.asm:7795-7847`) loads the caster's level, hit
rate, damage and class into `btlmag_attacker_*` variables that
no routine reads. The disassembly comment on the twin routine says
that one of those "should probably be intelligence".

The NES formulas:

```
hit_chance = 148 + spell_hitrate - target_magdef   (0 if resistant, +40 if weak)
roll = rand[0,200] ;  hits if hit_chance >= roll ;  roll==200 = automatic miss

base = spell_effectivity   ( /2 if resistant, *3/2 if weak )
dmg  = rand[base, base*2]
```

The detail that decides the choice: for **damage** spells, `hit_chance` doesn't
determine whether they hit — they always hit — it determines whether they **crit,
i.e. deal double damage** (`bank_0C.asm:8285`, `8326-8332`).

**Decision:**

```
hit_chance = 148 + spell_hitrate + (INT / 4) - target_magdef
```

One hook, two effects: utility spells (SLEP, MUTE, LOCK, XFER)
land more often, and attack spells deal more average damage through
crits. **The damage formula is untouched.**

The property that motivated the choice is about balance: against weak
targets `hit_chance` already breaks the 200 ceiling, so INT adds nothing;
the benefit appears **only against high MagDef**. An intelligent mage pierces
magic resistance, it doesn't inflate damage on trivial monsters. `INT/4` gives +0..+24
and is deliberately conservative: the constant is a value to be measured once
magic exists, the hook point isn't.

**INT is not magic defense**, and not for parity's sake: because MagDef already exists as a
real, separate stat — initial per class (`bank_0F.asm:1858`) plus a
per-level bonus capped at 200 (`bank_0B.asm:904-909`), and it doesn't derive from armor.
Folding INT into it would count the same thing twice. The structural reason
is stronger still: **enemies have MagDef but no INT**, so as
defense the calculation would be asymmetric between the two sides of the field, while as
accuracy the asymmetry is intended and readable.

- **Status:** ✅ **implemented in slice69** (`int_bonus` in `src/ovl_btlmagic.c`).
  It applies to the **party's** spells, in both paths where the
  hit chance matters: the crit of damage spells, the landing of
  ailments with effect `$03`, and nothing else. Monsters don't get it: their
  twenty stats in ROM contain no intelligence, and indeed the twin
  `magic_damage_on_chr` doesn't take the parameter.
  Field measurement, run `mame_drive_ailments.lua`: the black mage's SLEP (INT 20,
  i.e. +5) against an IMP (MagDef 16) gives `148 + 64 + 5 − 16 = 201` on a
  0-200 roll, i.e. it always lands except on a straight 200. Without INT it would be 196: four
  times out of two hundred SLEP would fail. It's little, and it's exactly the right scale —
  the `INT/4` constant was declared conservative and it is.

### 3.3bis The attacker's roll doesn't depend on the defender's sleep (slice69)

`DoPhysicalAttack` (`bank_0C.asm:4364-4372`) adds the **attacker's roll**
to the hit chance **only if the defender is awake**: the `@DefenderMobile` branch is
the `else` of the +25% damage bonus against those asleep or paralyzed. The
disassembly itself puts a *"This seems strange to me. Shouldn't this
be done even if defender is immobile? Is this BUGGED?"* on it.

The in-game effect: **putting an enemy to sleep worsens your own aim**. It's not
a trade-off — it's a `JMP` that skips too far, surrounded by three bonuses that
all add up without excluding each other.

**Fixed:** the roll is always added, the +25% stays. Combat formula
policy (`memory/ff1_engine_intent_priorities.md`, «combat/magic =
fix-default»). The fix makes SLEP and HOLD what they were meant to be: a
way to hit *better* those who don't move, not just harder.

### 3.3ter Silence silences, it doesn't gag (slice69)

On the NES `AIL_MUTE` blocks **spells, items and drinks** together
(`bank_0C.asm:7201`, complete with the comment *"You could argue this is BUGGED"*).
Here it blocks **only spells**: a silenced character can still drink a
potion, which is what silence means in every game that uses it.

The restriction is shown **before** opening the submenu — `SILENCED` on the
message line as soon as MAGIC is confirmed — and is rechecked at turn time: between
the choice and the action half a round passes, and a MUTE can arrive in between.

### 3.3quater Monsters really sleep (slice69, fix #14)

On the NES a sleeping monster **always wakes up on its first turn**. The branch is
broken in three places within the same dozen lines (`bank_0C.asm:6710-6730`):
it loads into `btl_mathbuf` a field (`en_unknown12`) that nobody initializes,
subtracts the random number from the wrong buffer, and then decides by looking at a sign
that `MathBuf_Sub` — which clamps to zero — can never produce.

The result is that SLEP, SLP2 and HOLD against monsters are worth **exactly one turn**,
always the same, regardless of everything.

**Fixed:** monsters use the same roll as characters, which is what the
code *declares* it wants to do — they wake up if `maxHP > rand[0,80]`. An IMP
(8 max HP) stays down about nine turns out of ten; a sturdy monster wakes up
almost immediately. Measured in the run: after two rounds, **3 of 4 sleeping IMPs
are still down**; with the NES defect it would have been zero.

Paralysis, on the other hand, keeps the NES asymmetry — 25% for characters, ~10%
for monsters. They are two different routines with two different constants, not a typo,
and neither of the two fix lists names it.

### 3.3quinquies The ailment is readable in the strip (slice69)

Each block of the status strip is four rows tall, and the fourth was empty.
Now it carries the ailment's name in full — `POISON`, `SLEEP`, `STONE`,
`CONFUSE` — instead of nothing.

It's not extra information compared to the NES: there the character's name changes
color and the status window writes it out anyway. It's just that here the TMS9918 can't
change the color of a single line of text without spending a color table,
while seven free characters were already there.

Only one at a time, the most serious, as on the NES: someone who's dead isn't also
«poisoned».

And `LAMP` on someone who can see perfectly well says **`INEFFECTIVE`** instead of silently
consuming the charge (`BtlMag_Effect_CureAilment` exits without saying anything,
`bank_0C.asm:8553`). Same rule as 1.6 and 1.6bis: a declared restriction doesn't
look like a defect.

### 3.3sexies The IB block — and the four dead spells it revives (slice70)

On the NES stats exist in two copies: `ch_stats` (*out-of-battle*, the ones
you carry around) and `btl_chstats` / `btl_enstats` (*in-battle*, which are born
at the start of the fight and die with it). Six spell effects out of eighteen
write to the second copy — FOG absorption, RUSE evasion, TMPR
strength, LOCK a monster's evasion, FAST hits, FEAR morale.

The ROM **saves that copy back wrong, and differently on the two sides**:

| routine | forgets | consequence |
|---|---|---|
| `BtlMag_SavePlayerDefenderStats` (`bank_0C.asm:8027`) | **strength** | TMPR and SABR do nothing — and always target a character |
| `BtlMag_SaveEnemyDefenderStats` (`bank_0C.asm:7982`) | **elemental resistance** | XFER does nothing on monsters (**fix #6**) |

Two routines, two forgotten fields, two dead spells each. Here the fields
are the **same for both sides of the field** and are written in the same place
(`src/battle_ibstats.h`): there's no place to forget one.

With the block, **all eighteen battle effects work.** The only ones left
out are LIFE, LIF2, SOFT, WARP and EXIT, which have effect `$00` because they are
spells meant to be used **outside** battle — and outside battle there isn't
yet a place to cast them from. What's missing is the menu, not the engine.

### 3.3septies LOK2 and HEL2 — the two corrected table entries (slice70)

The only two rows of `lut_MagicData` that the port doesn't use literally. The
fix lives in the engine (`patch_spell` in `src/ovl_btlmagic.c`), not
in the extractor: `src/data/magic_data.h` stays byte-exact with respect to the ROM, and the
deviation lives next to its reason.

- **LOK2 ($17)** declares effect `$10`, which **raises** evasion, and targets
  enemies. It's the opposite of what the name says and of what LOCK, its
  weak version, does: as it is, LOK2 spends a third-level charge to
  make a monster **harder** to hit. Read as `$0E`.
  The criterion, which would also apply to another entry of the same kind:
  *nobody buffs their own enemy.*
- **HEL2 ($23)** declares effectivity 48, the **same** as HEL3 ($33), which sits
  two levels above. 12 / 48 / 48 is not a progression; 12 / **24** / 48 is.

Plus two fixes that don't touch the table:

- **LOCK** (effect `$0E`) **always misses** on the NES: the routine has a `JMP` where
  a `BEQ` belonged and skips the whole body (`bank_0C.asm:8662`, annotated in the
  disassembly). Here the body runs.
- **SLOW and FAST tell the truth.** The NES declares the cast successful and *then*
  undoes the effect if the multiplier was already at its limit — so SLOW on someone
  already slow announces itself as working (`bank_0C.asm:8457`, "this is where the
  'bug' is"). Here the outcome follows the facts, and a wasted FAST says
  `INEFFECTIVE`.

### 3.4 Initiative shuffle — PRESERVED as is (slice59)

`DoBattleRound` (`bank_0C.asm:3211-3244`) shuffles the turn's 13 slots with
**16 swaps** of two randomly drawn positions. It's a weak shuffle, and the
disassembly notes it: a slot has a good chance of never being
touched, and since the characters start at the end of the list they tend to
stay there — so the enemies act first more often than an honest
shuffle would give.

**We keep it this way**, and it's the only case so far where an acknowledged defect
isn't fixed. Three reasons, in order of weight:

1. **The number of draws is part of the sequence.** 16 swaps = 32 calls
   to the generator. A Fisher-Yates would make 12 and would shift *every* subsequent
   roll of the fight. The parity of the whole battle goes through here,
   and it would be lost for a marginal gain.
2. **It's not a typo like LOK2**, which does the opposite of what it declares.
   This loop really shuffles; it shuffles badly. The distance between intent and
   implementation is one of degree, not of sign — and the fix list exists for the
   second case.
3. **The penalty is spread out**, not concentrated: it affects the pace of the whole
   game, not one encounter or one spell. Removing it would change the
   pace of the game more than it would correct it.

- **Status:** ✅ implemented NES-exact in slice59.

### 3.5 Defeat — declared placeholder (slice59)

The party can fall, and `run_defeat` shows "THE PARTY PERISHED". But then it
**puts everyone back on their feet with full HP** and returns to the overworld.

It's not a design choice: FF1's answer to a wipe is "reload the
save", and there's no save yet. Whatever is done here is
a placeholder, and it may as well be a declared one rather than one disguised
as a mechanic. It will go away together with the real Continue.

Also missing is the **silence**: the battle theme keeps playing under the
text, because stopping it would require a new `svc_`, i.e. bytes in the
fixed bank (169 free). It goes with the VFX session, together with the
screen shake.

**NES quirks PRESERVED:** see `memory/ff1_preserved_quirks.md` (Finger Point/PNEOP,
forced-fight retrigger, etc — beloved features that stay byte-exact).

---

## 4. Future / candidates (not yet implemented)

- **Save:** 4-trial password system (the NES had no password, only battery SRAM).
  For Coleco without a custom cart, password = the only mainstream choice.
- **Optional cart with SRAM:** if the CollectorVision community responds, a dedicated
  edition with full mid-dungeon save (true NES parity).
- **Phoenix SD detection:** save to SD if the Phoenix BIOS is detected (additive).
- **Battle target select via keypad:** numpad 1-9 for direct targeting (vs cycle).
- **Equipment menu UX:** keypad shortcut for a direct equip slot.
- **Subtle visual effects:** sprite zero-trick not available on Coleco;
  alternative Mode 2 raster effects via NMI ISR for HP-flash, dimming, etc.

---

## 4bis. Color rendering (porting choices, not improvements)

The TMS9918 has 15 fixed inks versus the NES's 52, and can only show
one per tile row. The decisions below are not "improvements": they are the
way we chose to LOSE information, and they are worth remembering because a
purist could legitimately prefer others.

- **Per-row dominant** (slice30 for the characters, slice55 for the enemies): among the
  lit pixels of each tile row, the most frequent color wins. The silhouettes
  stay faithful; the horizontal shading within a row is lost.
- **Palette swap preserved** (slice55): the NES enemy variants
  (IMP/GrIMP, WOLF/GrWOLF, SAHAG/R.SAHAG) stay distinct, because what is saved is
  the palette index, not the resolved color. This is full parity.
- **Palette collisions resolved by perceptual proximity** (slice55): 13
  FF1 palettes out of 64 send two of their three colors to the same TMS ink. In
  those cases one of the two entries is moved to the nearest free ink
  in redmean. It's a DEVIATION: the resulting color isn't the one that
  the conversion table would give. Without it, though, the IMP of the first encounter
  would have two colors instead of three.

- **Townspeople: silhouette in the background, outline as a sprite** (slice76). In Mode 2 a
  tile row has TWO colors, and an FF1 townsperson uses three -- terrain, body,
  black outline. The background carries the first two; a black 16x16 sprite puts
  the third on top. What's left out is the COLOR DETAIL inside the
  figure: skin and clothes become a single color per row (the dominant).
  And if the player stands next to a townsperson, its outline is the
  fifth sprite on the scanline and drops: the solid silhouette remains, readable.

- **The bridge: silhouette in the background instead of a sprite** (slice78). On the NES the
  overworld bridge is a 2x2 sprite drawn over the water. Here it's baked into the
  background, over the ocean macrotile it rests on, for the same reason
  as the townspeople: the mapman already takes up the four sprites the TMS shows per
  scanline, and the bridge would be the fifth -- it would vanish right while you're
  walking on it. The usual price of baking (the object can't move) isn't
  paid here: the bridge stays put in one cell by definition.
  Tile rows lying entirely on the bridge spend their two colors on the decking and
  the planks; those touching the water keep bridge and sea separate, so
  there the planks are lost.

- **The bridge scene's title card, in bitmap mode** (slice78). It's the only
  screen in the project where every cell has its own tile (Mode 2: 256
  patterns per screen third = one per cell). The picture fits WHOLE and
  without reuse; the only thing lost is the reduction to two colors per row of
  8 pixels. Measured on the FINAL FANTASY logo, which is the worst spot: 1.5%
  of letter pixels turning into sky, 0.3% of sky turning into letter.

### 4ter. The Nintendo credit is NOT there (slice78)

In the bridge scene's title card, the "TM&(C) 1990 NINTENDO" at the bottom
left is **removed**; the "(C)1987 SQUARE" at the bottom right **stays**.

It's not a technical limit: they are image cells like all the others, and they're
removed by filling them with the color around them (green meadow on the left,
black cliff on the right -- a solid color in both cases, so nothing gets
reconstructed and no seam shows). It's a choice, and it's a
switch in the extractor (`-DropNintendo` / `-DropSquare`):

- **Nintendo published the NES version** and has nothing to do with a ColecoVision
  port. Leaving its mark would be a false attribution --
  it would suggest a license that doesn't exist.
- **Square wrote the game** this port comes from, and that line is
  true. Removing it would erase the attribution to those who made the work.

## 5. Philosophy

- **Default = NES parity** (gameplay, balancing, encounter rates, music timing,
  text content, screen layout).
- **Additions =** only where the NES was limited by hardware/cart cost, and the Coleco
  allows lifting that limit (more RAM with SGM, keypad input, AY voice).
- **Bug fixes =** where there's clearly an "intent vs implementation" gap (AstralEsper
  guide). We don't touch beloved bug-features (PNEOP, etc).
- **Additive stack:** every improvement must be disable-able / ignore-able by a
  NES-purist player. No removal of NES features.
