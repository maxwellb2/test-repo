-- Interactive LOVE sandbox UI for Balatro Lab.
-- Immediate-mode: panels are drawn and hit-tested each frame against a single
-- pending click captured on mousepressed (see ui/widgets.lua).

local W = require("ui.widgets")
local scoring = require("engine.scoring")
local jokers = require("engine.jokers")
local Card = require("engine.card")
local cards_data = require("data.cards")
local hand_levels = require("data.hand_levels")
local decks_data = require("data.decks")
local blinds_data = require("data.blinds")

local app = {}

-- Cyclable option lists.
local ENH   = { "none", "bonus", "mult", "wild", "glass", "steel", "stone", "gold", "lucky" }
local EDS   = { "none", "foil", "holographic", "polychrome" }
local SEALS = { "none", "gold", "red", "blue", "purple" }
local JOKER_EDS = { "none", "foil", "holographic", "polychrome", "negative" }

local state
local result
local focus_search = false
local search = ""
local catalog_scroll = 0
local breakdown_scroll = 0

local function default_card(rank, suit, loc)
    return Card.new({ rank = rank, suit = suit, location = loc or "played" })
end

local function reset_state()
    state = {
        played = {
            default_card("A", "Spades"),
            default_card("A", "Hearts"),
            default_card("K", "Clubs"),
            default_card("Q", "Diamonds"),
            default_card("10", "Spades"),
        },
        held = {},
        jokers = {},
        levels = {},
        config = {
            deck = "red", boss = "none", money = 4,
            hands_left = 1, discards_left = 0, joker_slots = 5,
            last_hand = false, hand_played_this_round = false,
            hand_override = "", observatory_hands = {},
        },
    }
end

local function recompute()
    result = scoring.evaluate({
        played = state.played,
        held = state.held,
        jokers = state.jokers,
        levels = state.levels,
        config = state.config,
    })
end

function app.load()
    love.keyboard.setKeyRepeat(true)
    reset_state()
    recompute()
end

function app.update(dt) end

function app.mousepressed(x, y, button)
    W.click = { x = x, y = y, button = button }
    focus_search = false -- panels re-set this if the search box is clicked
end

function app.wheelmoved(dx, dy)
    W.scroll_dy = dy
end

function app.keypressed(key)
    if focus_search then
        if key == "backspace" then
            search = search:sub(1, -2)
        end
    end
    if key == "escape" then love.event.quit() end
end

function app.textinput(t)
    if focus_search then search = search .. t end
end

-- ---- panels are defined below; draw() wires them together ----
local draw_cards, draw_jokers, draw_globals, draw_levels, draw_result

function app.draw()
    W.begin_frame()
    love.graphics.clear(W.palette.bg)

    recompute()

    W.text("BALATRO LAB", 16, 10, W.palette.accent)
    W.text("Scoring Sandbox - v1.0.1n parity target", 130, 14, W.palette.dim)

    draw_cards(16, 40, 360)
    draw_jokers(388, 40, 372)
    draw_globals(772, 40, 250)
    draw_levels(772, 360, 250)
    draw_result(1032, 40, 272)

    W.end_frame()
end

local P = W.palette

-- Draw + edit a single playing card. Mutates `card` in place.
local function draw_card(card, x, y, w, h, index, list_name)
    local list = state[list_name]
    W.rect("fill", x, y, w, h, P.panel2, card.debuffed and 0.5 or 1)
    W.rect("line", x, y, w, h, P.accent, 0.5)

    card.rank = W.cycler(x + 2, y + 2, w / 2 - 3, 38, "rank", card.rank, cards_data.RANKS)
    local suit_short = card.suit:sub(1, 1)
    local new_suit = W.cycler(x + w / 2, y + 2, w / 2 - 2, 38, "suit", suit_short, { "S", "H", "C", "D" })
    local suit_map = { S = "Spades", H = "Hearts", C = "Clubs", D = "Diamonds" }
    card.suit = suit_map[new_suit]

    card.enhancement = W.cycler(x + 2, y + 42, w - 4, 20, "enh", card.enhancement, ENH)
    card.edition = W.cycler(x + 2, y + 64, w - 4, 20, "edit", card.edition, EDS)
    card.seal = W.cycler(x + 2, y + 86, w - 4, 20, "seal", card.seal, SEALS)

    local bw = (w - 8) / 3
    if W.button(x + 2, y + 110, bw, 18, "del") then
        table.remove(list, index)
    end
    local move_label = list_name == "played" and ">hold" or ">play"
    if W.button(x + 4 + bw, y + 110, bw, 18, move_label) then
        local c = table.remove(list, index)
        c.location = list_name == "played" and "held" or "played"
        table.insert(state[c.location], c)
    end
    if W.button(x + 6 + bw * 2, y + 110, bw, 18, card.debuffed and "dbf!" or "dbf",
        { active = card.debuffed }) then
        card.debuffed = not card.debuffed
    end
end

function draw_cards(x, y, w)
    W.text(string.format("PLAYED  ->  %s (lvl %d)", result.hand, result.level), x, y, P.text)
    local cw, ch, gap = 112, 132, 6
    for i, card in ipairs(state.played) do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        draw_card(card, x + col * (cw + gap), y + 24 + row * (ch + gap), cw, ch, i, "played")
    end
    local prows = math.ceil((#state.played) / 3)
    local addy = y + 24 + math.max(prows, 1) * (ch + gap)
    if #state.played < 5 then
        if W.button(x, addy, 120, 22, "+ played card", { color = P.accent }) then
            table.insert(state.played, default_card("A", "Spades", "played"))
        end
    end

    local hy = addy + 32
    W.text("HELD (in hand)", x, hy, P.dim)
    for i, card in ipairs(state.held) do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        draw_card(card, x + col * (cw + gap), hy + 20 + row * (ch + gap), cw, ch, i, "held")
    end
    local hrows = math.ceil((#state.held) / 3)
    local haddy = hy + 20 + math.max(hrows, 0) * (ch + gap)
    if #state.held < 5 then
        if W.button(x, haddy + (#state.held > 0 and 0 or 0), 120, 22, "+ held card", { color = P.accent2 }) then
            table.insert(state.held, default_card("K", "Spades", "held"))
        end
    end
end

function draw_result(x, y, w)
    W.rect("fill", x, y, w, 78, P.panel)
    W.text("SCORE", x + 8, y + 6, P.dim)
    W.set_color(P.text)
    love.graphics.setNewFont(30)
    love.graphics.printf(tostring(result.score), x, y + 22, w - 8, "right")
    love.graphics.setNewFont(12)
    W.set_color(P.chip)
    love.graphics.print(string.format("%g chips", result.chips), x + 8, y + 56)
    W.set_color(P.mult)
    love.graphics.printf(string.format("x %g mult", result.mult), x, y + 56, w - 8, "right")

    W.text("BREAKDOWN", x, y + 88, P.dim)
    local panel_y, panel_h = y + 106, 660
    W.rect("fill", x, panel_y, w, panel_h, P.panel2)
    if W.is_hovered(x, panel_y, w, panel_h) then
        breakdown_scroll = breakdown_scroll - W.scroll_dy * 3
    end
    local lines = result.breakdown:render()
    local total = #lines * 16
    breakdown_scroll = math.max(0, math.min(breakdown_scroll, math.max(0, total - panel_h + 10)))
    love.graphics.setScissor(x, panel_y, w, panel_h)
    for i, line in ipairs(lines) do
        W.text(line, x + 6, panel_y + 4 + (i - 1) * 16 - breakdown_scroll, P.text)
    end
    love.graphics.setScissor()
end

-- Compact +/- numeric stepper. Returns the new value.
local function stepper(x, y, label, value, step, minv, maxv)
    W.text(label, x, y + 2, P.dim)
    if W.button(x + 92, y, 20, 18, "-") then value = value - step end
    W.set_color(P.text)
    love.graphics.printf(string.format("%g", value), x + 112, y + 2, 44, "center")
    if W.button(x + 158, y, 20, 18, "+") then value = value + step end
    if minv and value < minv then value = minv end
    if maxv and value > maxv then value = maxv end
    return value
end

-- Generic editor for a joker's mutable state (counters, xmults, suit/rank).
local function draw_joker_state(j, x, y, w)
    local keys = {}
    for k in pairs(j.state) do keys[#keys + 1] = k end
    table.sort(keys)
    local cx = x
    for _, k in ipairs(keys) do
        local v = j.state[k]
        if type(v) == "boolean" then
            if W.button(cx, y, 64, 18, k .. ":" .. (v and "Y" or "N"), { active = v }) then
                j.state[k] = not v
            end
            cx = cx + 70
        elseif type(v) == "number" then
            local step = tostring(k):find("xmult") and 0.1 or 1
            W.text(k, cx, y + 2, P.dim)
            local lblw = 8 + #k * 6
            if W.button(cx + lblw, y, 16, 18, "-") then j.state[k] = v - step end
            W.set_color(P.text)
            love.graphics.print(string.format("%g", j.state[k]), cx + lblw + 18, y + 2)
            if W.button(cx + lblw + 54, y, 16, 18, "+") then j.state[k] = j.state[k] + step end
            cx = cx + lblw + 76
        elseif type(v) == "string" then
            if k == "suit" then
                j.state[k] = W.cycler(cx, y, 70, 18, k, v, cards_data.SUITS)
                cx = cx + 76
            elseif k == "rank" then
                j.state[k] = W.cycler(cx, y, 50, 18, k, v, cards_data.RANKS)
                cx = cx + 56
            end
        end
    end
end

function draw_jokers(x, y, w)
    local active_h = 380
    W.text(string.format("JOKERS  (%d / %d slots)", #state.jokers, state.config.joker_slots),
        x, y, P.text)
    W.rect("fill", x, y + 20, w, active_h, P.panel)

    love.graphics.setScissor(x, y + 20, w, active_h)
    local rowh = 64
    for i, j in ipairs(state.jokers) do
        local def = jokers.by_id[j.id]
        local ry = y + 24 + (i - 1) * rowh
        W.rect("fill", x + 2, ry, w - 4, rowh - 4, P.panel2, j.enabled and 1 or 0.4)
        W.text(def.name, x + 8, ry + 4, P.text)
        W.text(def.rarity, x + 8, ry + 20, P.dim)
        if def.note then W.text(def.note:sub(1, 44), x + 8, ry + 34, P.dim) end

        j.edition = W.cycler(x + w - 110, ry + 2, 80, 20, "ed", j.edition, JOKER_EDS)
        if W.button(x + w - 26, ry + 2, 22, 20, j.enabled and "on" or "off", { active = j.enabled }) then
            j.enabled = not j.enabled
        end
        if W.button(x + w - 110, ry + 24, 24, 18, "up") and i > 1 then
            state.jokers[i], state.jokers[i - 1] = state.jokers[i - 1], state.jokers[i]
        end
        if W.button(x + w - 84, ry + 24, 24, 18, "dn") and i < #state.jokers then
            state.jokers[i], state.jokers[i + 1] = state.jokers[i + 1], state.jokers[i]
        end
        if W.button(x + w - 30, ry + 24, 26, 18, "del", { color = P.mult }) then
            table.remove(state.jokers, i)
        end
        draw_joker_state(j, x + 8, ry + rowh - 24, w - 16)
    end
    love.graphics.setScissor()

    -- Catalog / search
    local cy = y + 20 + active_h + 8
    W.text("ADD JOKER", x, cy, P.dim)
    local sb_y = cy + 16
    local focused = focus_search
    W.rect("fill", x, sb_y, w, 22, P.panel2, focused and 1 or 0.7)
    W.text(search == "" and "type to search..." or search, x + 6, sb_y + 4,
        search == "" and P.dim or P.text)
    if W.clicked(x, sb_y, w, 22) then focus_search = true end

    local list_y, list_h = sb_y + 28, 282
    W.rect("fill", x, list_y, w, list_h, P.panel)
    if W.is_hovered(x, list_y, w, list_h) then
        catalog_scroll = catalog_scroll - W.scroll_dy * 18
    end
    local needle = search:lower()
    local matches = {}
    for _, id in ipairs(jokers.order) do
        local def = jokers.by_id[id]
        if needle == "" or def.name:lower():find(needle, 1, true) then
            matches[#matches + 1] = def
        end
    end
    local total = #matches * 18
    catalog_scroll = math.max(0, math.min(catalog_scroll, math.max(0, total - list_h)))
    love.graphics.setScissor(x, list_y, w, list_h)
    for i, def in ipairs(matches) do
        local ry = list_y + (i - 1) * 18 - catalog_scroll
        if W.button(x + 2, ry, w - 4, 17, def.name .. "   (" .. def.rarity .. ")") then
            table.insert(state.jokers, jokers.instance(def.id))
        end
    end
    love.graphics.setScissor()
end

function draw_globals(x, y, w)
    W.text("GLOBAL MODIFIERS", x, y, P.text)
    local gy = y + 22
    W.rect("fill", x, gy, w, 270, P.panel)
    gy = gy + 6
    local cfg = state.config

    local deck_id = W.cycler(x + 6, gy, w - 12, 22, "deck", cfg.deck, decks_data.ORDER)
    cfg.deck = deck_id
    W.text(decks_data.DECKS[cfg.deck].name, x + 6, gy + 2, P.dim)
    gy = gy + 26

    cfg.boss = W.cycler(x + 6, gy, w - 12, 22, "boss", cfg.boss, blinds_data.ORDER)
    W.text(blinds_data.BLINDS[cfg.boss].name, x + 6, gy + 2, P.dim)
    gy = gy + 26

    local override_list = { "(auto)" }
    for _, h in ipairs(hand_levels.ORDER) do override_list[#override_list + 1] = h end
    local cur_override = cfg.hand_override == "" and "(auto)" or cfg.hand_override
    local new_override = W.cycler(x + 6, gy, w - 12, 22, "force hand", cur_override, override_list)
    cfg.hand_override = (new_override == "(auto)") and "" or new_override
    gy = gy + 28

    cfg.money = stepper(x + 6, gy, "money $", cfg.money, 1, 0); gy = gy + 22
    cfg.hands_left = stepper(x + 6, gy, "hands left", cfg.hands_left, 1, 0); gy = gy + 22
    cfg.discards_left = stepper(x + 6, gy, "discards", cfg.discards_left, 1, 0); gy = gy + 22
    cfg.joker_slots = stepper(x + 6, gy, "joker slots", cfg.joker_slots, 1, 0); gy = gy + 26

    if W.button(x + 6, gy, 116, 20, "last hand: " .. (cfg.last_hand and "Y" or "N"),
        { active = cfg.last_hand }) then
        cfg.last_hand = not cfg.last_hand
    end
    if W.button(x + 128, gy, 116, 20, "obs " .. result.hand:sub(1, 6) .. ": " ..
        ((cfg.observatory_hands[result.hand]) and "Y" or "N"),
        { active = cfg.observatory_hands[result.hand] }) then
        cfg.observatory_hands[result.hand] = not cfg.observatory_hands[result.hand]
    end
    gy = gy + 24
    if W.button(x + 6, gy, 116, 20, "hand replayed: " .. (cfg.hand_played_this_round and "Y" or "N"),
        { active = cfg.hand_played_this_round }) then
        cfg.hand_played_this_round = not cfg.hand_played_this_round
    end
    if W.button(x + 128, gy, 116, 20, "RESET ALL", { color = P.mult }) then
        reset_state()
    end
end

function draw_levels(x, y, w)
    W.text("HAND LEVELS", x, y, P.text)
    local ly = y + 22
    W.rect("fill", x, ly, w, 300, P.panel)
    for i, name in ipairs(hand_levels.ORDER) do
        local ry = ly + 4 + (i - 1) * 24
        local lvl = state.levels[name] or 1
        local hi = (name == result.hand)
        W.text(name, x + 6, ry + 4, hi and P.good or P.text)
        if W.button(x + w - 86, ry + 2, 20, 20, "-") then
            state.levels[name] = math.max(1, lvl - 1)
        end
        W.set_color(P.text)
        love.graphics.printf("lvl " .. lvl, x + w - 66, ry + 4, 40, "center")
        if W.button(x + w - 22, ry + 2, 20, 20, "+") then
            state.levels[name] = lvl + 1
        end
    end
end

return app
