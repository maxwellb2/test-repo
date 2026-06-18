-- Playing card model + small helpers used by the scoring engine.

local cards_data = require("data.cards")

local M = {}

-- Build a normalized card table. All fields optional except rank/suit (unless
-- it is a stone card, which has neither).
function M.new(opts)
    opts = opts or {}
    return {
        rank = opts.rank or "A",
        suit = opts.suit or "Spades",
        enhancement = opts.enhancement or "none",
        edition = opts.edition or "none",
        seal = opts.seal or "none",
        debuffed = opts.debuffed or false,
        location = opts.location or "played", -- "played" | "held"
    }
end

-- A stone card has no rank/suit and does not participate in hand-type matching.
function M.is_stone(card)
    return card.enhancement == "stone"
end

-- Cards that contribute to determining the poker hand type. Debuffed cards and
-- stone cards (no rank/suit) are excluded from type matching.
function M.contributes_to_type(card)
    return not card.debuffed and not M.is_stone(card)
end

-- Base chip value of a card's rank (0 for stone, which adds chips via its
-- enhancement instead).
function M.rank_chips(card)
    if M.is_stone(card) then
        return 0
    end
    return cards_data.RANK_CHIPS[card.rank] or 0
end

-- Numeric rank order for straight detection.
function M.rank_order(card)
    return cards_data.RANK_ORDER[card.rank]
end

-- Effective suits of a card. Wild cards count as every suit; smeared (Smeared
-- Joker) pairs Hearts<->Diamonds and Spades<->Clubs.
function M.suits_of(card, smeared)
    if M.is_stone(card) then
        return {}
    end
    if card.enhancement == "wild" then
        return { "Spades", "Hearts", "Clubs", "Diamonds" }
    end
    if smeared then
        if card.suit == "Hearts" or card.suit == "Diamonds" then
            return { "Hearts", "Diamonds" }
        else
            return { "Spades", "Clubs" }
        end
    end
    return { card.suit }
end

function M.has_suit(card, suit, smeared)
    for _, s in ipairs(M.suits_of(card, smeared)) do
        if s == suit then
            return true
        end
    end
    return false
end

function M.is_face(card)
    if M.is_stone(card) then
        return false
    end
    return card.rank == "J" or card.rank == "Q" or card.rank == "K"
end

return M
