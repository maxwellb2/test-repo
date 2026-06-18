-- Boss blind effects relevant to scoring / hand selection.
-- Many boss blinds affect draw/economy and are out of scope; the scoring and
-- selection-relevant ones are modeled here.

local M = {}

M.ORDER = { "none", "the_flint", "the_eye", "the_arm", "the_psychic" }

M.BLINDS = {
    none = { name = "None" },
    the_flint = {
        name = "The Flint",
        -- Base chips and mult of the played hand are halved (after level lookup,
        -- before card/joker scoring).
        halve_base = true,
    },
    the_eye = {
        name = "The Eye",
        -- No played hand type may be repeated this round. Selection constraint
        -- only; no direct scoring change. Surfaced as a note in the UI.
        note = "No repeat hand types this round",
    },
    the_arm = {
        name = "The Arm",
        -- Decreases the level of the played hand by 1 (min level 1).
        level_down = 1,
    },
    the_psychic = {
        name = "The Psychic",
        note = "Must play 5 cards",
    },
}

return M
