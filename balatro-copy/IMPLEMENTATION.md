# Balatro Lab - Implementation Status

Tracks current coverage against the PRD. Target version: **Balatro v1.0.1n**.

## Running

- **UI (sandbox):** from the repo root run `love balatro-copy`
  (or `cd balatro-copy && love .`). Requires [LÖVE 11.x](https://love2d.org/).
- **Headless tests:** `love balatro-copy test` (uses LÖVE's bundled LuaJIT, no
  system Lua needed). If you have a standalone Lua: `lua balatro-copy/tests/run.lua`.
- **UI smoke test:** `love balatro-copy smoke`.

## Layout

```
balatro-copy/
|-- main.lua          # LOVE entry point (ui / test / smoke modes)
|-- conf.lua          # window config
|-- engine/           # pure-Lua scoring core (headless-testable)
|   |-- card.lua      # card model + helpers
|   |-- hands.lua     # poker hand detection (+ four fingers / shortcut / smeared / splash)
|   |-- query.lua     # read-only helpers for joker effects
|   |-- score.lua     # score accumulator + breakdown log
|   |-- scoring.lua   # evaluation order orchestrator
|   `-- jokers.lua    # data-driven joker catalog (148 entries)
|-- data/             # version-pinned constants
|   |-- cards.lua     # ranks, suits, chips, enhancements, editions, seals
|   |-- hand_levels.lua
|   |-- decks.lua / vouchers.lua / blinds.lua
|-- ui/               # LOVE front-end
|   |-- widgets.lua   # immediate-mode widget helpers
|   `-- app.lua       # panels: cards, jokers, globals, levels, breakdown
`-- tests/            # cases.lua (logic) + run.lua (standalone entry)
```

## Engine coverage

| Area | Status |
| --- | --- |
| All 12 poker hands + per-level scaling | Done |
| Hand auto-detection + manual override | Done |
| Low-ace straights, four-fingers, shortcut, smeared, splash | Done |
| Card chips by rank | Done |
| Enhancements (bonus/mult/wild/glass/steel/stone/gold/lucky) | Done |
| Editions (foil/holo/poly) on cards + jokers | Done |
| Seals (red retrigger; gold/blue/purple economy noted) | Done |
| Held-in-hand effects (steel + on-held jokers) | Done |
| Retriggers (red seal, Hack, Sock & Buskin, Hanging Chad, Dusk, Seltzer, Mime) | Done |
| Joker timing: on_scored / on_held / independent + edition pass | Done |
| Deck: Plasma (balance + x2) | Done |
| Vouchers: Observatory (per-hand x1.5) | Done |
| Boss blinds: The Flint (halve), The Arm (level down), The Eye/Psychic (notes) | Done |
| Probabilistic effects via manual toggles (lucky cards, prob jokers) | Done |

## Joker catalog

148 jokers are defined (`engine/jokers.lua`). Each is either:

- **Scored** - a working `on_scored` / `on_held` / `independent` / `retrigger` /
  `detection` hook that affects the score, or
- **Noted** - economy / card-generation / between-round jokers that have no
  single-hand scoring effect; they appear in the catalog with an explanatory
  note (and no score impact), e.g. Credit Card, Rocket, Marble Joker.

### Accumulating jokers
Jokers whose value grows over a run (Ride the Bus, Green Joker, Obelisk,
Hologram, Vampire, Constellation, Supernova, Castle, Runner, Square Joker, etc.)
expose their stored value as **editable state** in the UI, so you set the
current value to match your live game.

### Known simplifications (v1)
- **Blueprint / Brainstorm** do not auto-copy a neighbour's effect; configure the
  copied effect by adding the target joker directly. (Planned follow-up.)
- **Hiker** applies its +5 chips for the current hand only (no persistent deck
  mutation, which is out of scope for a single-hand sandbox).
- **Joker Stencil** uses `joker slots - active jokers + 1`; set the slot count in
  the global panel to match your run.
- Probabilistic jokers (Bloodstone, Lucky cards, etc.) assume the trigger fires;
  toggle the per-instance `trigger` state (or per-card lucky flag) off to model a
  miss.

## Tests
`tests/cases.lua` covers hand detection, levels, card properties, retriggers,
held steel, joker ordering (additive-then-multiplicative), joker editions, and
global modifiers (Flint, Plasma). All passing.

## Not implemented (per PRD non-goals)
Deck draw / shuffle, economy simulation, run/ante progression, save/load/share,
and the optional optimizer (M7 stretch).
