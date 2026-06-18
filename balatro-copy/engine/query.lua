-- Read-only helpers for inspecting the played/scored cards. Used by joker
-- definitions so each joker stays a small declarative effect.

local Card = require("engine.card")

local M = {}

function M.rank_counts(cards)
    local c = {}
    for _, card in ipairs(cards) do
        if not Card.is_stone(card) then
            c[card.rank] = (c[card.rank] or 0) + 1
        end
    end
    return c
end

function M.max_group(cards)
    local m = 0
    for _, n in pairs(M.rank_counts(cards)) do
        if n > m then m = n end
    end
    return m
end

function M.pair_count(cards)
    local p = 0
    for _, n in pairs(M.rank_counts(cards)) do
        if n >= 2 then p = p + 1 end
    end
    return p
end

function M.count_suit(cards, suit, smeared)
    local n = 0
    for _, card in ipairs(cards) do
        if Card.has_suit(card, suit, smeared) then n = n + 1 end
    end
    return n
end

function M.count_face(cards)
    local n = 0
    for _, card in ipairs(cards) do
        if Card.is_face(card) then n = n + 1 end
    end
    return n
end

function M.count_rank(cards, rank)
    local n = 0
    for _, card in ipairs(cards) do
        if card.rank == rank then n = n + 1 end
    end
    return n
end

-- Even ranks: 2,4,6,8,10. Odd: A,3,5,7,9 (Ace counts as odd in Balatro).
function M.is_even(card)
    local r = card.rank
    return r == "2" or r == "4" or r == "6" or r == "8" or r == "10"
end

function M.is_odd(card)
    local r = card.rank
    return r == "A" or r == "3" or r == "5" or r == "7" or r == "9"
end

-- Whether the played hand "contains" a given feature, used by the
-- conditional jokers (Jolly, Zany, Sly, etc.).
function M.hand_contains(ctx, feature)
    local cards = ctx.scoring_cards
    local name = ctx.hand_name
    if feature == "pair" then
        return M.max_group(cards) >= 2
    elseif feature == "two_pair" then
        return M.pair_count(cards) >= 2
    elseif feature == "three" then
        return M.max_group(cards) >= 3
    elseif feature == "four" then
        return M.max_group(cards) >= 4
    elseif feature == "straight" then
        return name == "Straight" or name == "Straight Flush"
    elseif feature == "flush" then
        return name == "Flush" or name == "Straight Flush"
            or name == "Flush House" or name == "Flush Five"
    end
    return false
end

return M
