-- Scoring-relevant vouchers. Most vouchers are economy/shop related and out of
-- scope; only those that change a hand's score are modeled.

local M = {}

M.ORDER = { "observatory" }

M.VOUCHERS = {
    observatory = {
        name = "Observatory",
        -- Planet cards in your consumable area give x1.5 mult for that hand
        -- type. In the sandbox this is exposed as a per-hand toggle on the
        -- global config (observatory_hands[hand_name] = true).
        hand_xmult = 1.5,
    },
}

return M
