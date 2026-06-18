-- Poker hand base scoring and per-level scaling, pinned to Balatro v1.0.1n.
-- A hand at level N scores: chips = base_chips + (N-1)*chip_per_level,
--                           mult  = base_mult  + (N-1)*mult_per_level.

local M = {}

-- Ordered strongest -> weakest. Hand detection walks this order and returns the
-- first match (with the relevant scoring cards).
M.ORDER = {
    "Flush Five",
    "Flush House",
    "Five of a Kind",
    "Straight Flush",
    "Four of a Kind",
    "Full House",
    "Flush",
    "Straight",
    "Three of a Kind",
    "Two Pair",
    "Pair",
    "High Card",
}

M.HANDS = {
    ["High Card"]       = { base_chips = 5,   base_mult = 1,  chip_per_level = 10, mult_per_level = 1 },
    ["Pair"]            = { base_chips = 10,  base_mult = 2,  chip_per_level = 15, mult_per_level = 1 },
    ["Two Pair"]        = { base_chips = 20,  base_mult = 2,  chip_per_level = 20, mult_per_level = 1 },
    ["Three of a Kind"] = { base_chips = 30,  base_mult = 3,  chip_per_level = 20, mult_per_level = 2 },
    ["Straight"]        = { base_chips = 30,  base_mult = 4,  chip_per_level = 30, mult_per_level = 3 },
    ["Flush"]           = { base_chips = 35,  base_mult = 4,  chip_per_level = 15, mult_per_level = 2 },
    ["Full House"]      = { base_chips = 40,  base_mult = 4,  chip_per_level = 25, mult_per_level = 2 },
    ["Four of a Kind"]  = { base_chips = 60,  base_mult = 7,  chip_per_level = 30, mult_per_level = 3 },
    ["Straight Flush"]  = { base_chips = 100, base_mult = 8,  chip_per_level = 40, mult_per_level = 4 },
    ["Five of a Kind"]  = { base_chips = 120, base_mult = 12, chip_per_level = 35, mult_per_level = 3 },
    ["Flush House"]     = { base_chips = 140, base_mult = 14, chip_per_level = 40, mult_per_level = 4 },
    ["Flush Five"]      = { base_chips = 160, base_mult = 16, chip_per_level = 50, mult_per_level = 3 },
}

-- Returns base chips and mult for a hand at a given level (level >= 1).
function M.values(hand_name, level)
    local h = M.HANDS[hand_name]
    if not h then
        error("unknown hand: " .. tostring(hand_name))
    end
    level = math.max(1, level or 1)
    local chips = h.base_chips + (level - 1) * h.chip_per_level
    local mult = h.base_mult + (level - 1) * h.mult_per_level
    return chips, mult
end

return M
