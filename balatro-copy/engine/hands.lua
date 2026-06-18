-- Poker hand detection. Returns the detected hand name plus the list of
-- *scoring* cards (the subset of played cards that actually contribute
-- chips/mult). Supports joker-driven detection modifiers:
--   opts.four_fingers : flushes/straights need only 4 cards
--   opts.shortcut     : straights may contain gaps of 1
--   opts.smeared      : suits pair up for flush detection
--   opts.splash       : every played card scores regardless of hand

local Card = require("engine.card")

local unpack = table.unpack or unpack

local M = {}

local function distinct_sorted_orders(cards)
    local seen, list = {}, {}
    for _, c in ipairs(cards) do
        local o = Card.rank_order(c)
        if o and not seen[o] then
            seen[o] = true
            list[#list + 1] = o
        end
    end
    table.sort(list)
    return list
end

-- Detect a straight among the contributing cards. Returns true if found.
local function is_straight(cards, need, shortcut)
    local orders = distinct_sorted_orders(cards)
    if #orders < need then
        return false
    end

    -- Build candidate sequences including the low-Ace alias (Ace = 1).
    local function check(seq)
        table.sort(seq)
        local run = 1
        for i = 2, #seq do
            local gap = seq[i] - seq[i - 1]
            if gap == 1 or (shortcut and gap == 2) then
                run = run + 1
                if run >= need then
                    return true
                end
            elseif gap == 0 then
                -- duplicate, ignore
            else
                run = 1
            end
        end
        return run >= need
    end

    if check({ unpack(orders) }) then
        return true
    end
    -- Low ace: treat Ace(14) as 1 as well.
    local has_ace = false
    for _, o in ipairs(orders) do
        if o == 14 then has_ace = true end
    end
    if has_ace then
        local alias = { 1 }
        for _, o in ipairs(orders) do
            if o ~= 14 then alias[#alias + 1] = o end
        end
        if check(alias) then
            return true
        end
    end
    return false
end

-- Count cards by rank (contributing cards only).
local function rank_counts(cards)
    local counts = {}
    for _, c in ipairs(cards) do
        counts[c.rank] = (counts[c.rank] or 0) + 1
    end
    return counts
end

-- Is there a flush? Accounts for wild cards and smeared suits.
local function is_flush(cards, need, smeared)
    if #cards < need then
        return false
    end
    for _, suit in ipairs({ "Spades", "Hearts", "Clubs", "Diamonds" }) do
        local n = 0
        for _, c in ipairs(cards) do
            if Card.has_suit(c, suit, smeared) then
                n = n + 1
            end
        end
        if n >= need then
            return true
        end
    end
    return false
end

-- Returns the n highest cards belonging to ranks whose count == group_size.
local function cards_in_groups(cards, counts, group_size, max_groups)
    -- Collect ranks with exactly group_size (or more handled by caller order).
    local chosen_ranks = {}
    for rank, n in pairs(counts) do
        if n == group_size then
            chosen_ranks[#chosen_ranks + 1] = rank
        end
    end
    -- Highest ranks first.
    table.sort(chosen_ranks, function(a, b)
        return (require("data.cards").RANK_ORDER[a] or 0) > (require("data.cards").RANK_ORDER[b] or 0)
    end)
    if max_groups then
        for i = #chosen_ranks, max_groups + 1, -1 do
            chosen_ranks[i] = nil
        end
    end
    local want = {}
    for _, r in ipairs(chosen_ranks) do want[r] = true end
    local out = {}
    for _, c in ipairs(cards) do
        if want[c.rank] then
            out[#out + 1] = c
        end
    end
    return out, chosen_ranks
end

-- Main entry point.
-- played: array of card tables (location == "played")
-- opts:   detection modifiers (see top of file)
-- Returns: hand_name, scoring_cards
function M.detect(played, opts)
    opts = opts or {}
    local flush_need = opts.four_fingers and 4 or 5
    local straight_need = opts.four_fingers and 4 or 5

    -- Cards that determine the type (exclude debuffed + stone).
    local contrib = {}
    for _, c in ipairs(played) do
        if Card.contributes_to_type(c) then
            contrib[#contrib + 1] = c
        end
    end

    -- Cards that always score regardless of type (stone, non-debuffed).
    local always_score = {}
    for _, c in ipairs(played) do
        if Card.is_stone(c) and not c.debuffed then
            always_score[#always_score + 1] = c
        end
    end

    local counts = rank_counts(contrib)
    local flush = is_flush(contrib, flush_need, opts.smeared)
    local straight = is_straight(contrib, straight_need, opts.shortcut)

    -- Max group size and pair count.
    local max_group, pair_count = 0, 0
    for _, n in pairs(counts) do
        if n > max_group then max_group = n end
        if n >= 2 then pair_count = pair_count + 1 end
    end

    -- All non-debuffed played cards (used for whole-hand types).
    local all_non_debuffed = {}
    for _, c in ipairs(played) do
        if not c.debuffed then
            all_non_debuffed[#all_non_debuffed + 1] = c
        end
    end

    local function finalize(name, scoring)
        -- Splash: every played card scores.
        if opts.splash then
            scoring = all_non_debuffed
        else
            -- Always merge in stone cards.
            local present = {}
            for _, c in ipairs(scoring) do present[c] = true end
            local merged = {}
            for _, c in ipairs(scoring) do merged[#merged + 1] = c end
            for _, c in ipairs(always_score) do
                if not present[c] then merged[#merged + 1] = c end
            end
            scoring = merged
        end
        return name, scoring
    end

    -- Strongest -> weakest.
    if flush and max_group >= 5 then
        return finalize("Flush Five", all_non_debuffed)
    end
    if flush and max_group == 3 and pair_count >= 2 then
        return finalize("Flush House", all_non_debuffed)
    end
    if max_group >= 5 then
        return finalize("Five of a Kind", cards_in_groups(contrib, counts, max_group, 1))
    end
    if flush and straight then
        return finalize("Straight Flush", all_non_debuffed)
    end
    if max_group >= 4 then
        return finalize("Four of a Kind", cards_in_groups(contrib, counts, 4, 1))
    end
    if max_group == 3 and pair_count >= 2 then
        return finalize("Full House", all_non_debuffed)
    end
    if flush then
        return finalize("Flush", all_non_debuffed)
    end
    if straight then
        return finalize("Straight", all_non_debuffed)
    end
    if max_group == 3 then
        return finalize("Three of a Kind", cards_in_groups(contrib, counts, 3, 1))
    end
    if pair_count >= 2 then
        return finalize("Two Pair", (cards_in_groups(contrib, counts, 2, 2)))
    end
    if max_group == 2 then
        return finalize("Pair", (cards_in_groups(contrib, counts, 2, 1)))
    end

    -- High card: highest single contributing card.
    local high = nil
    for _, c in ipairs(contrib) do
        if not high or (Card.rank_order(c) or 0) > (Card.rank_order(high) or 0) then
            high = c
        end
    end
    return finalize("High Card", high and { high } or {})
end

return M
