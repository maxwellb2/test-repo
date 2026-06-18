# PRD: Balatro Scoring Sandbox ("Balatro Lab") — v1.0 (Final)

## 1. Overview
A standalone, fully-configurable **scoring sandbox** for Balatro, written in Lua with a
**LÖVE (Love2D)** UI. It is **not** the game — no deck draw, no economy, no run
progression, no win/lose loop. It lets a user hand-build an exact scenario (played + held
cards, card properties, hand levels, jokers and their state, global modifiers) and see the
resulting score with a transparent, step-by-step breakdown.

Intended to be used **alongside** a live game: "I have these jokers and this hand — what
will it score, and which ordering is best?"

Behavior/parity reference: the [efhiii Balatro Calculator](https://efhiii.github.io/balatro-calculator/).

## 2. Target Version (locked)
- **Target Balatro patch: v1.0.1n** — the steam patch that finalized core scoring/balance
  values before cosmetic-only updates.
- **Parity rule:** when in doubt, scoring output must match the efhiii reference calculator
  on identical inputs. If a value ever conflicts, the reference calculator wins and we note
  the deviation.
- All scoring constants (base chips/mult per hand level, enhancement/edition/seal values,
  per-joker math) are pinned to this version in data files.

## 3. Goals
- Reproduce v1.0.1n scoring math **accurately**, matching the reference calculator on
  identical inputs.
- Expose **full optionality**: every card property, all 12 hand levels, **all ~150
  jokers**, and the major global modifiers.
- Everything **selectable and editable at runtime** — no recompiling to change a scenario.
- Produce a clear **breakdown log** (ordered record of every chip/mult change), not just a
  final number.
- **Data-driven** jokers/cards so the full catalog is defined declaratively.

## 4. Non-Goals
- No card drawing, shuffling, deck depletion, or shop/economy simulation.
- No ante/blind progression or full-run state.
- **No saving, loading, importing, exporting, or scenario sharing.** Each session is
  configured fresh and lives only in memory.
- No multiplayer.
- Not pixel-perfect art; a clean **functional UI** is sufficient for v1.

## 5. Domain Model

### 5.1 Playing Card (editable properties)
- **Rank**: A, 2–10, J, Q, K (chips: face = 10, Ace = 11, number = pip value).
- **Suit**: Spades, Hearts, Clubs, Diamonds.
- **Enhancement** (one): None, Bonus (+30 chips), Mult (+4 mult), Wild (any suit),
  Glass (×2 mult, 1-in-4 shatter), Steel (×1.5 mult while **held**), Stone (+50 chips,
  no rank/suit), Gold (+$3 if held at round end), Lucky (1-in-5 +20 mult, 1-in-15 +$20).
- **Edition** (one): None, Foil (+50 chips), Holographic (+10 mult), Polychrome (×1.5 mult).
- **Seal** (one): None, Gold (+$3 when scored), Red (retrigger once), Blue (creates Planet),
  Purple (creates Tarot on discard).
- **Debuffed**: boolean.
- **Location**: `played` or `held` (held matters for Steel and held-in-hand joker triggers).

### 5.2 Poker Hands & Levels
All 12 hands, each with editable **level** → base chips/mult lookup:
High Card, Pair, Two Pair, Three of a Kind, Straight, Flush, Full House, Four of a Kind,
Straight Flush, Five of a Kind, Flush House, Flush Five.
- Played hand type is **auto-detected** and **manually overridable**.

### 5.3 Jokers — full catalog (~150)
Ordered list (order matters). Each instance:
- **Type** (any of the full v1.0.1n catalog).
- **Edition**: None, Foil, Holographic, Polychrome, Negative (Negative adds a joker slot).
- **Enabled/disabled**, **debuffed** flags.
- **Mutable state** where applicable (counters/stored values, e.g., Ride the Bus, Green
  Joker, Obelisk, Hologram, Rocket) — directly editable.
- Sell value field (parity/completeness; not used in scoring).
- Jokers are **data-defined**: each entry declares its trigger timing (on-scored / on-held /
  independent / on-played) and effect, so all ~150 are expressible without engine changes.

### 5.4 Global / Run Modifiers
- **Deck type**: incl. Plasma (balance chips & mult, then ×2) and others affecting scoring.
- **Vouchers** affecting scoring (e.g., Observatory: ×1.5 mult for hand types with a Planet
  in consumables).
- **Boss blind effects**: The Flint (halve base chips & mult), The Eye (can't replay a hand
  type), card-debuff blinds, etc.
- **Counters**: hands left, discards left, money (for jokers that scale off them).

## 6. Functional Requirements

### 6.1 Hand Builder
- Up to **5 played cards** in the scoring area.
- Configurable **held (in-hand) cards** that aren't played but affect Steel/held triggers
  (**full support**).
- Per-card editor for all §5.1 properties.
- Reorder played cards; "clear hand" and "reset all."

### 6.2 Hand Level Panel
- All 12 hands listed with editable level + live base chips/mult display.
- Manual override of detected hand type.

### 6.3 Joker Configuration
- Add/remove from a **searchable catalog of all ~150 jokers**.
- Reorder (up/down or drag).
- Per-joker editor: edition, enable/disable, debuff, and any mutable counters/state.
- Joker slot count display (Negative editions add slots).

### 6.4 Global Modifier Panel
- Select deck type, toggle relevant vouchers, select boss blind effect, set hands/discards
  left and money.

### 6.5 Probabilistic Effects — manual toggle
- Lucky cards, Glass shatter, all 1-in-X jokers: each random outcome is a **manual toggle**
  ("assume it triggers" on/off), matching the reference calculator's checkbox behavior. No
  averaging/EV in v1.

### 6.6 Scoring Engine + Breakdown
- "Play hand" computes the score via the canonical evaluation order (§7).
- Output **final score** + an ordered **breakdown log**: each event (card scored →
  +chips/×mult, joker triggered, retrigger, deck multiplier) with running chips/mult totals.
- Explicit handling/logging of **retriggers** (Red seal, retrigger jokers).

## 7. Scoring Algorithm (Evaluation Order)
1. Detect played hand → base chips & mult for its level.
2. Apply boss-blind base modifiers (e.g., The Flint halves base).
3. Score each **played** card left→right: card chips, enhancement chips, edition chips,
   then card mult effects, applying retriggers per card.
4. **Held-in-hand** effects: Steel cards (×1.5 mult), held-card joker triggers.
5. **Jokers** left→right: add chips / add mult / ×mult; joker edition bonus applies after
   the joker's own effect.
6. **Deck/global** multipliers (e.g., Plasma balance + ×2).
7. Final score = chips × mult.

Order-sensitivity (additive-then-multiplicative jokers) is the primary correctness risk and
must match the reference.

## 8. Technical Architecture
- **Engine** (`engine/`): pure Lua, no render deps → headless-testable, reused by the UI.
- **Data** (`data/`): declarative Lua tables for cards, hand levels, all ~150 jokers, decks,
  vouchers, blinds — pinned to v1.0.1n.
- **UI** (`ui/`): **LÖVE (Love2D)** front-end.
- **Tests** (`tests/`): known input→score cases validated against the reference calculator,
  including order-sensitive and retrigger scenarios.

```text
balatro-copy/
|-- engine/        # scoring core (headless, pure Lua)
|-- data/          # cards, hand levels, jokers (~150), decks, vouchers, blinds
|-- ui/            # Love2D interface
|-- tests/         # parity tests vs reference calculator
|-- main.lua       # LOVE entry point (delegates to ui/)
`-- PRD.md
```

## 9. Data Model Sketch
```lua
-- Card
{ rank="K", suit="Hearts", enhancement="glass", edition="polychrome",
  seal="red", debuffed=false, location="played" }

-- Joker instance
{ id="ride_the_bus", edition="holographic", enabled=true, debuffed=false,
  state={ mult=12 }, sell_value=6 }

-- Joker definition (data-driven)
{ id="ride_the_bus", name="Ride the Bus", rarity="common", timing="independent",
  defaults={ mult=0 }, apply=function(ctx, joker) ... end }

-- Hand levels
{ Flush=3, Pair=1, --[[ ...all 12... ]] }

-- Global config
{ deck="plasma", vouchers={ observatory=true }, boss="the_flint",
  hands_left=3, discards_left=2, money=25 }
```

## 10. Non-Functional Requirements
- **Accuracy**: exact integer score parity with the reference calculator on covered cases.
- **Extensibility**: all jokers data-defined; engine handles them via timing + effect hooks.
- **Transparency**: every score fully explained by the breakdown log.
- **Version pinning**: all constants tied to v1.0.1n.

## 11. Milestones
1. **M1 – Engine core**: base hands + levels + card chips/mult → final score; headless tests.
2. **M2 – Card properties**: all enhancements, editions, seals, retriggers (played + held).
3. **M3 – Jokers framework + first batch**: data-driven joker system + common jokers.
4. **M4 – Full joker catalog**: remaining jokers to reach all ~150, with manual prob toggles.
5. **M5 – Globals**: deck types, vouchers, boss blinds, counters.
6. **M6 – LÖVE UI**: full editing of cards/held/jokers/levels/globals + breakdown panel.
7. **M7 (stretch) – Optimizers**: "optimize joker order" / "optimize cards to play". Optional.

## 12. Acceptance Criteria (v1)
- User can build up to 5 played + N held cards, edit every property, set all 12 hand levels,
  add/order any of the ~150 jokers with editable state/edition, and configure
  deck/voucher/boss/counters.
- All random effects are manual toggles.
- "Play hand" returns a final score plus a complete, ordered breakdown.
- Scores match the efhiii reference calculator on the test suite.
- No save/load/share anywhere in the app.

## 13. Implementation Status
See `IMPLEMENTATION.md` for current coverage of the joker catalog and engine features.
Run the headless test suite with: `lua tests/run.lua` (works with Lua 5.1+/LuaJIT).
Run the UI with: `love balatro-copy` (from the repo root) or `love .` inside this folder.
