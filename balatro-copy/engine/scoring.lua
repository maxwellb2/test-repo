-- Core scoring engine. Implements Balatro's canonical evaluation order and
-- produces a Score object with a full breakdown log.
--
-- Evaluation order (see PRD section 7):
--   1. detect hand -> base chips/mult at level (boss + observatory adjustments)
--   2. score each scoring card left->right (with retriggers)
--   3. held-in-hand effects (steel + on-held jokers, with retriggers)
--   4. independent jokers left->right (+ joker editions)
--   5. deck/global multipliers (Plasma)
--   6. final = floor(chips * mult)

local Card = require("engine.card")
local Hands = require("engine.hands")
local Score = require("engine.score")
local cards_data = require("data.cards")
local hand_levels = require("data.hand_levels")
local decks_data = require("data.decks")
local vouchers_data = require("data.vouchers")
local blinds_data = require("data.blinds")
local jokers_catalog = require("engine.jokers")

local M = {}

-- Build detection options (Four Fingers, Shortcut, etc.) from active jokers.
local function detection_opts(jokers)
    local opts = {}
    for _, j in ipairs(jokers) do
        if j.enabled ~= false and not j.debuffed then
            local def = jokers_catalog.by_id[j.id]
            if def and def.detection then
                for k, v in pairs(def.detection) do
                    opts[k] = v
                end
            end
        end
    end
    return opts
end

-- Apply the chips/mult/xmult contributions of a single scoring card.
local function score_card_once(ctx, card)
    local label = (card.rank or "?") .. " of " .. (card.suit or "?")
    if Card.is_stone(card) then label = "Stone card" end

    ctx:add_chips(Card.rank_chips(card), label)

    local enh = cards_data.ENHANCEMENTS[card.enhancement]
    if enh then
        if enh.chips then ctx:add_chips(enh.chips, enh.name .. " card") end
        if enh.mult then ctx:add_mult(enh.mult, enh.name .. " card") end
        if enh.xmult then ctx:x_mult(enh.xmult, enh.name .. " card") end
        if enh.lucky and card.lucky_trigger ~= false then
            ctx:add_mult(20, "Lucky card")
        end
    end

    local ed = cards_data.EDITIONS[card.edition]
    if ed then
        if ed.chips then ctx:add_chips(ed.chips, ed.name .. " edition") end
        if ed.mult then ctx:add_mult(ed.mult, ed.name .. " edition") end
        if ed.xmult then ctx:x_mult(ed.xmult, ed.name .. " edition") end
    end
end

-- How many times a scored card triggers (1 + red seal + joker retriggers).
local function scored_retriggers(ctx, card)
    local n = 1
    if card.seal == "red" then n = n + 1 end
    for _, j in ipairs(ctx.jokers) do
        if j.enabled ~= false and not j.debuffed then
            local def = jokers_catalog.by_id[j.id]
            if def and def.retrigger_scored then
                n = n + (def.retrigger_scored(ctx, card, j) or 0)
            end
        end
    end
    return n
end

local function held_retriggers(ctx, card)
    local n = 1
    if card.seal == "red" then n = n + 1 end
    for _, j in ipairs(ctx.jokers) do
        if j.enabled ~= false and not j.debuffed then
            local def = jokers_catalog.by_id[j.id]
            if def and def.retrigger_held then
                n = n + (def.retrigger_held(ctx, card, j) or 0)
            end
        end
    end
    return n
end

-- Apply a joker's edition bonus (foil/holographic/polychrome). Negative has no
-- scoring effect (only adds a slot).
local function apply_joker_edition(ctx, joker)
    local ed = cards_data.EDITIONS[joker.edition]
    if not ed then return end
    local name = (jokers_catalog.by_id[joker.id] and jokers_catalog.by_id[joker.id].name or joker.id)
    if ed.chips then ctx:add_chips(ed.chips, name .. " (Foil)") end
    if ed.mult then ctx:add_mult(ed.mult, name .. " (Holo)") end
    if ed.xmult then ctx:x_mult(ed.xmult, name .. " (Poly)") end
end

-- scenario fields:
--   played   : array of played card tables
--   held     : array of held card tables (optional)
--   levels   : map hand_name -> level (optional, default 1)
--   jokers   : ordered array of joker instances (optional)
--   config   : global modifiers (optional)
-- Returns: result table { hand, level, chips, mult, score, breakdown(Score) }
function M.evaluate(scenario)
    local played = scenario.played or {}
    local held = scenario.held or {}
    local levels = scenario.levels or {}
    local jokers = scenario.jokers or {}
    local config = scenario.config or {}

    local opts = detection_opts(jokers)
    local hand_name, scoring_cards = Hands.detect(played, opts)
    if config.hand_override and config.hand_override ~= "" then
        hand_name = config.hand_override
    end

    local level = levels[hand_name] or 1
    local boss = blinds_data.BLINDS[config.boss or "none"]
    if boss and boss.level_down then
        level = math.max(1, level - boss.level_down)
    end

    local base_chips, base_mult = hand_levels.values(hand_name, level)
    if boss and boss.halve_base then
        base_chips = math.floor(base_chips / 2)
        base_mult = math.floor(base_mult / 2)
    end

    local ctx = Score.new(base_chips, base_mult)
    ctx:note(string.format("%s (lvl %d) base", hand_name, level))

    -- Shared context for joker hooks.
    ctx.hand_name = hand_name
    ctx.hand_level = level
    ctx.played = played
    ctx.held = held
    ctx.scoring_cards = scoring_cards
    ctx.jokers = jokers
    ctx.config = config
    ctx.catalog = jokers_catalog

    -- Pareidolia: every card is treated as a face card (affects face-based jokers).
    for _, j in ipairs(jokers) do
        if j.id == "pareidolia" and j.enabled ~= false and not j.debuffed then
            ctx.pareidolia = true
        end
    end

    -- ---- Step 2: score each scoring card (in played order) ----
    -- Iterate played order but only those flagged as scoring.
    local is_scoring = {}
    for _, c in ipairs(scoring_cards) do is_scoring[c] = true end

    for _, card in ipairs(played) do
        if is_scoring[card] then
            local triggers = scored_retriggers(ctx, card)
            for t = 1, triggers do
                if t > 1 then ctx:note("Retrigger") end
                score_card_once(ctx, card)
                for _, j in ipairs(jokers) do
                    if j.enabled ~= false and not j.debuffed then
                        local def = jokers_catalog.by_id[j.id]
                        if def and def.on_scored then def.on_scored(ctx, card, j) end
                    end
                end
            end
        end
    end

    -- ---- Step 3: held-in-hand effects ----
    for _, card in ipairs(held) do
        if not card.debuffed then
            local triggers = held_retriggers(ctx, card)
            for t = 1, triggers do
                if t > 1 then ctx:note("Retrigger (held)") end
                local enh = cards_data.ENHANCEMENTS[card.enhancement]
                if enh and enh.held_xmult then
                    ctx:x_mult(enh.held_xmult, enh.name .. " card (held)")
                end
                for _, j in ipairs(jokers) do
                    if j.enabled ~= false and not j.debuffed then
                        local def = jokers_catalog.by_id[j.id]
                        if def and def.on_held then def.on_held(ctx, card, j) end
                    end
                end
            end
        end
    end

    -- ---- Step 4: independent jokers (+ editions) ----
    for _, j in ipairs(jokers) do
        if j.enabled ~= false and not j.debuffed then
            local def = jokers_catalog.by_id[j.id]
            if def and def.independent then def.independent(ctx, j) end
            apply_joker_edition(ctx, j)
        end
    end

    -- Observatory voucher: x1.5 mult for hands whose Planet is in consumables.
    if config.observatory_hands and config.observatory_hands[hand_name] then
        ctx:x_mult(vouchers_data.VOUCHERS.observatory.hand_xmult, "Observatory")
    end

    -- ---- Step 5: deck / global multipliers ----
    local deck = decks_data.DECKS[config.deck or "red"]
    if deck and deck.balance then
        local avg = (ctx.chips + ctx.mult) / 2
        ctx.chips = avg
        ctx.mult = avg
        ctx:note("Plasma Deck (balanced)")
    end
    if deck and deck.final_xmult then
        ctx:x_mult(deck.final_xmult, "Plasma Deck")
    end

    -- ---- Step 6: final ----
    local score = math.floor(ctx.chips * ctx.mult + 0.5)

    return {
        hand = hand_name,
        level = level,
        chips = ctx.chips,
        mult = ctx.mult,
        score = score,
        breakdown = ctx,
    }
end

return M
