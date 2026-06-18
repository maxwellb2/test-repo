-- Card-related constants pinned to Balatro v1.0.1n.
-- Ranks, suits, chip values, and the enums for enhancements / editions / seals.

local M = {}

-- Display order for ranks (low -> high). Ace is high for straights but also
-- usable as low (A-2-3-4-5) which is handled in hand detection.
M.RANKS = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A" }

-- Base chip value contributed by a card of each rank when scored.
M.RANK_CHIPS = {
    ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6,
    ["7"] = 7, ["8"] = 8, ["9"] = 9, ["10"] = 10,
    ["J"] = 10, ["Q"] = 10, ["K"] = 10, ["A"] = 11,
}

-- Numeric ordering used for straight detection. Ace is 14 (high); low-ace
-- straights are handled explicitly in the detector.
M.RANK_ORDER = {
    ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6,
    ["7"] = 7, ["8"] = 8, ["9"] = 9, ["10"] = 10,
    ["J"] = 11, ["Q"] = 12, ["K"] = 13, ["A"] = 14,
}

M.SUITS = { "Spades", "Hearts", "Clubs", "Diamonds" }

-- Enhancements. `chips` and `mult` are flat adds applied when the card scores;
-- `xmult` is a multiplier applied to mult when the card scores. Steel applies
-- its xmult only while the card is *held* (not played).
M.ENHANCEMENTS = {
    none  = { name = "None" },
    bonus = { name = "Bonus", chips = 30 },
    mult  = { name = "Mult", mult = 4 },
    wild  = { name = "Wild", any_suit = true },
    glass = { name = "Glass", xmult = 2, destroy_chance = "1 in 4" },
    steel = { name = "Steel", held_xmult = 1.5 },
    stone = { name = "Stone", chips = 50, no_rank = true, always_scores = true },
    gold  = { name = "Gold", money_eor = 3 },
    lucky = { name = "Lucky", lucky = true }, -- 1 in 5: +20 mult, 1 in 15: +$20
}

-- Editions for playing cards (negative is joker-only in practice).
M.EDITIONS = {
    none        = { name = "None" },
    foil        = { name = "Foil", chips = 50 },
    holographic = { name = "Holographic", mult = 10 },
    polychrome  = { name = "Polychrome", xmult = 1.5 },
    negative    = { name = "Negative", slot = 1 },
}

M.SEALS = {
    none   = { name = "None" },
    gold   = { name = "Gold", money_scored = 3 },
    red    = { name = "Red", retrigger = 1 },
    blue   = { name = "Blue" },   -- creates Planet if held at end of round
    purple = { name = "Purple" }, -- creates Tarot on discard
}

return M
