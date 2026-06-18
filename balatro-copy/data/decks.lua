-- Deck definitions. Only scoring-relevant behavior is modeled (per non-goals,
-- economy / draw / hand-size effects are out of scope for the sandbox).

local M = {}

M.ORDER = { "red", "plasma" }

M.DECKS = {
    red = {
        name = "Red Deck",
        -- No scoring effect (gives +1 discard in-game).
    },
    plasma = {
        name = "Plasma Deck",
        -- Before the final chips*mult, average chips and mult together so they
        -- are equal, then multiply the final score by 2.
        balance = true,
        final_xmult = 2,
    },
}

return M
