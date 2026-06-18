-- Joker catalog (Balatro v1.0.1n). Data-driven: each entry declares optional
-- hooks the scoring engine calls. Hooks:
--   on_scored(ctx, card, joker)  : per scored card
--   on_held(ctx, card, joker)    : per held card
--   independent(ctx, joker)      : once, after cards
--   retrigger_scored/held(...)   : extra retriggers for a card
--   detection = { four_fingers/shortcut/smeared/splash }
-- `defaults` provides editable mutable state (counters/xmults) for jokers that
-- accumulate value over a run; the sandbox lets users set these directly.
--
-- Jokers whose effects are purely economy / card-generation / between-round are
-- listed with no scoring hook (note only) so they still appear in the catalog.

local Q = require("engine.query")

local function is_face(ctx, card)
    return require("engine.card").is_face(card) or ctx.pareidolia
end

local function count_rarity(ctx, rarity)
    local n = 0
    for _, j in ipairs(ctx.jokers) do
        local def = ctx.catalog.by_id[j.id]
        if def and def.rarity == rarity and j.enabled ~= false and not j.debuffed then
            n = n + 1
        end
    end
    return n
end

local function joker_count(ctx)
    local n = 0
    for _, j in ipairs(ctx.jokers) do
        if j.enabled ~= false then n = n + 1 end
    end
    return n
end

local defs = {}
local function add(def) defs[#defs + 1] = def end

-- ===================== COMMON =====================

add({ id = "joker", name = "Joker", rarity = "Common",
    independent = function(ctx) ctx:add_mult(4, "Joker") end })

add({ id = "greedy_joker", name = "Greedy Joker", rarity = "Common",
    on_scored = function(ctx, c) if require("engine.card").has_suit(c, "Diamonds") then ctx:add_mult(3, "Greedy Joker") end end })
add({ id = "lusty_joker", name = "Lusty Joker", rarity = "Common",
    on_scored = function(ctx, c) if require("engine.card").has_suit(c, "Hearts") then ctx:add_mult(3, "Lusty Joker") end end })
add({ id = "wrathful_joker", name = "Wrathful Joker", rarity = "Common",
    on_scored = function(ctx, c) if require("engine.card").has_suit(c, "Spades") then ctx:add_mult(3, "Wrathful Joker") end end })
add({ id = "gluttonous_joker", name = "Gluttonous Joker", rarity = "Common",
    on_scored = function(ctx, c) if require("engine.card").has_suit(c, "Clubs") then ctx:add_mult(3, "Gluttonous Joker") end end })

add({ id = "jolly_joker", name = "Jolly Joker", rarity = "Common",
    independent = function(ctx) if Q.hand_contains(ctx, "pair") then ctx:add_mult(8, "Jolly Joker") end end })
add({ id = "zany_joker", name = "Zany Joker", rarity = "Common",
    independent = function(ctx) if Q.hand_contains(ctx, "three") then ctx:add_mult(12, "Zany Joker") end end })
add({ id = "mad_joker", name = "Mad Joker", rarity = "Common",
    independent = function(ctx) if Q.hand_contains(ctx, "two_pair") then ctx:add_mult(10, "Mad Joker") end end })
add({ id = "crazy_joker", name = "Crazy Joker", rarity = "Common",
    independent = function(ctx) if Q.hand_contains(ctx, "straight") then ctx:add_mult(12, "Crazy Joker") end end })
add({ id = "droll_joker", name = "Droll Joker", rarity = "Common",
    independent = function(ctx) if Q.hand_contains(ctx, "flush") then ctx:add_mult(10, "Droll Joker") end end })

add({ id = "sly_joker", name = "Sly Joker", rarity = "Common",
    independent = function(ctx) if Q.hand_contains(ctx, "pair") then ctx:add_chips(50, "Sly Joker") end end })
add({ id = "wily_joker", name = "Wily Joker", rarity = "Common",
    independent = function(ctx) if Q.hand_contains(ctx, "three") then ctx:add_chips(100, "Wily Joker") end end })
add({ id = "clever_joker", name = "Clever Joker", rarity = "Common",
    independent = function(ctx) if Q.hand_contains(ctx, "two_pair") then ctx:add_chips(80, "Clever Joker") end end })
add({ id = "devious_joker", name = "Devious Joker", rarity = "Common",
    independent = function(ctx) if Q.hand_contains(ctx, "straight") then ctx:add_chips(100, "Devious Joker") end end })
add({ id = "crafty_joker", name = "Crafty Joker", rarity = "Common",
    independent = function(ctx) if Q.hand_contains(ctx, "flush") then ctx:add_chips(80, "Crafty Joker") end end })

add({ id = "half_joker", name = "Half Joker", rarity = "Common",
    independent = function(ctx) if #ctx.played <= 3 then ctx:add_mult(20, "Half Joker") end end })

add({ id = "credit_card", name = "Credit Card", rarity = "Common",
    note = "Go up to -$20 in debt (economy, no scoring)" })
add({ id = "banner", name = "Banner", rarity = "Common",
    independent = function(ctx) ctx:add_chips(30 * (ctx.config.discards_left or 0), "Banner") end })
add({ id = "mystic_summit", name = "Mystic Summit", rarity = "Common",
    independent = function(ctx) if (ctx.config.discards_left or 0) == 0 then ctx:add_mult(15, "Mystic Summit") end end })
add({ id = "8_ball", name = "8 Ball", rarity = "Common",
    note = "Chance to create Tarot from played Aces (generation, no scoring)" })
add({ id = "misprint", name = "Misprint", rarity = "Common", defaults = { mult = 23 },
    independent = function(ctx, j) ctx:add_mult(j.state.mult, "Misprint") end })
add({ id = "raised_fist", name = "Raised Fist", rarity = "Common",
    independent = function(ctx)
        local lowest
        for _, c in ipairs(ctx.held) do
            if not require("engine.card").is_stone(c) then
                local o = require("engine.card").rank_order(c)
                if not lowest or o < lowest then lowest = o end
            end
        end
        if lowest then ctx:add_mult(2 * lowest, "Raised Fist") end
    end })
add({ id = "fibonacci", name = "Fibonacci", rarity = "Uncommon",
    on_scored = function(ctx, c)
        local r = c.rank
        if r == "A" or r == "2" or r == "3" or r == "5" or r == "8" then
            ctx:add_mult(8, "Fibonacci")
        end
    end })
add({ id = "scary_face", name = "Scary Face", rarity = "Common",
    on_scored = function(ctx, c) if is_face(ctx, c) then ctx:add_chips(30, "Scary Face") end end })
add({ id = "abstract_joker", name = "Abstract Joker", rarity = "Common",
    independent = function(ctx) ctx:add_mult(3 * joker_count(ctx), "Abstract Joker") end })
add({ id = "delayed_gratification", name = "Delayed Gratification", rarity = "Common",
    note = "Earn money if no discards used (economy)" })
add({ id = "gros_michel", name = "Gros Michel", rarity = "Common",
    independent = function(ctx) ctx:add_mult(15, "Gros Michel") end })
add({ id = "even_steven", name = "Even Steven", rarity = "Common",
    on_scored = function(ctx, c) if Q.is_even(c) then ctx:add_mult(4, "Even Steven") end end })
add({ id = "odd_todd", name = "Odd Todd", rarity = "Common",
    on_scored = function(ctx, c) if Q.is_odd(c) then ctx:add_chips(31, "Odd Todd") end end })
add({ id = "scholar", name = "Scholar", rarity = "Common",
    on_scored = function(ctx, c) if c.rank == "A" then ctx:add_chips(20, "Scholar"); ctx:add_mult(4, "Scholar") end end })
add({ id = "business_card", name = "Business Card", rarity = "Common",
    note = "Face cards have a chance to give $2 (economy)" })
add({ id = "supernova", name = "Supernova", rarity = "Common", defaults = { count = 1 },
    independent = function(ctx, j) ctx:add_mult(j.state.count, "Supernova") end })
add({ id = "ride_the_bus", name = "Ride the Bus", rarity = "Common", defaults = { mult = 0 },
    independent = function(ctx, j) ctx:add_mult(j.state.mult, "Ride the Bus") end })
add({ id = "egg", name = "Egg", rarity = "Common", note = "Gains sell value (economy)" })
add({ id = "runner", name = "Runner", rarity = "Common", defaults = { chips = 0 },
    independent = function(ctx, j) ctx:add_chips(j.state.chips, "Runner") end })
add({ id = "ice_cream", name = "Ice Cream", rarity = "Common", defaults = { chips = 100 },
    independent = function(ctx, j) ctx:add_chips(j.state.chips, "Ice Cream") end })
add({ id = "splash", name = "Splash", rarity = "Common", detection = { splash = true },
    note = "Every played card counts in scoring" })
add({ id = "blue_joker", name = "Blue Joker", rarity = "Common", defaults = { cards_left = 52 },
    independent = function(ctx, j) ctx:add_chips(2 * j.state.cards_left, "Blue Joker") end })
add({ id = "faceless_joker", name = "Faceless Joker", rarity = "Common",
    note = "Earn money for discarding 3+ face cards (economy)" })
add({ id = "green_joker", name = "Green Joker", rarity = "Common", defaults = { mult = 0 },
    independent = function(ctx, j) ctx:add_mult(j.state.mult, "Green Joker") end })
add({ id = "superposition", name = "Superposition", rarity = "Common",
    note = "Create Tarot on Ace + Straight (generation)" })
add({ id = "to_do_list", name = "To Do List", rarity = "Common",
    note = "Earn money for a specific hand type (economy)" })
add({ id = "cavendish", name = "Cavendish", rarity = "Common",
    independent = function(ctx) ctx:x_mult(3, "Cavendish") end })
add({ id = "red_card", name = "Red Card", rarity = "Common", defaults = { mult = 0 },
    independent = function(ctx, j) ctx:add_mult(j.state.mult, "Red Card") end })
add({ id = "square_joker", name = "Square Joker", rarity = "Common", defaults = { chips = 0 },
    independent = function(ctx, j) ctx:add_chips(j.state.chips, "Square Joker") end })
add({ id = "riff_raff", name = "Riff-Raff", rarity = "Common",
    note = "Create Common Jokers on blind (generation)" })
add({ id = "photograph", name = "Photograph", rarity = "Common",
    on_scored = function(ctx, c)
        if is_face(ctx, c) and not ctx._photo_used then
            ctx._photo_used = true
            ctx:x_mult(2, "Photograph")
        end
    end })
add({ id = "reserved_parking", name = "Reserved Parking", rarity = "Common",
    note = "Held face cards have a chance to give $1 (economy)" })
add({ id = "mail_in_rebate", name = "Mail-In Rebate", rarity = "Common",
    note = "Earn money per discarded rank (economy)" })
add({ id = "hallucination", name = "Hallucination", rarity = "Common",
    note = "Chance for Tarot on booster open (generation)" })
add({ id = "fortune_teller", name = "Fortune Teller", rarity = "Common", defaults = { mult = 0 },
    independent = function(ctx, j) ctx:add_mult(j.state.mult, "Fortune Teller") end })
add({ id = "juggler", name = "Juggler", rarity = "Common", note = "+1 hand size (no scoring)" })
add({ id = "drunkard", name = "Drunkard", rarity = "Common", note = "+1 discard (no scoring)" })
add({ id = "golden_joker", name = "Golden Joker", rarity = "Common",
    note = "Earn $4 at end of round (economy)" })

-- ===================== UNCOMMON =====================

add({ id = "joker_stencil", name = "Joker Stencil", rarity = "Uncommon",
    independent = function(ctx, j)
        local slots = ctx.config.joker_slots or 5
        local empty = math.max(0, slots - joker_count(ctx))
        local x = empty + 1 -- Joker Stencil counts itself
        if x > 1 then ctx:x_mult(x, "Joker Stencil") end
    end })
add({ id = "four_fingers", name = "Four Fingers", rarity = "Uncommon",
    detection = { four_fingers = true }, note = "Flushes & Straights need only 4 cards" })
add({ id = "mime", name = "Mime", rarity = "Uncommon",
    retrigger_held = function() return 1 end, note = "Retrigger all held cards" })
add({ id = "ceremonial_dagger", name = "Ceremonial Dagger", rarity = "Uncommon", defaults = { mult = 0 },
    independent = function(ctx, j) ctx:add_mult(j.state.mult, "Ceremonial Dagger") end })
add({ id = "marble_joker", name = "Marble Joker", rarity = "Uncommon",
    note = "Adds a Stone card to deck on blind (no scoring)" })
add({ id = "loyalty_card", name = "Loyalty Card", rarity = "Uncommon", defaults = { active = false },
    independent = function(ctx, j) if j.state.active then ctx:x_mult(4, "Loyalty Card") end end })
add({ id = "dusk", name = "Dusk", rarity = "Uncommon",
    retrigger_scored = function(ctx) return (ctx.config.last_hand) and 1 or 0 end,
    note = "Retrigger all played cards on final hand" })
add({ id = "chaos_the_clown", name = "Chaos the Clown", rarity = "Common",
    note = "1 free reroll per shop (economy)" })
add({ id = "steel_joker", name = "Steel Joker", rarity = "Uncommon", defaults = { steel_in_deck = 0 },
    independent = function(ctx, j)
        local x = 1 + 0.2 * (j.state.steel_in_deck or 0)
        if x > 1 then ctx:x_mult(x, "Steel Joker") end
    end })
add({ id = "hack", name = "Hack", rarity = "Uncommon",
    retrigger_scored = function(ctx, c)
        if c.rank == "2" or c.rank == "3" or c.rank == "4" or c.rank == "5" then return 1 end
        return 0
    end })
add({ id = "pareidolia", name = "Pareidolia", rarity = "Uncommon",
    note = "All cards are considered face cards" })
add({ id = "space_joker", name = "Space Joker", rarity = "Uncommon",
    note = "1 in 4 chance to upgrade played hand level (no immediate scoring)" })
add({ id = "burglar", name = "Burglar", rarity = "Uncommon",
    note = "Trade discards for hands (no scoring)" })
add({ id = "blackboard", name = "Blackboard", rarity = "Uncommon",
    independent = function(ctx)
        local all_dark = true
        for _, c in ipairs(ctx.held) do
            local C = require("engine.card")
            if not (C.has_suit(c, "Spades") or C.has_suit(c, "Clubs")) then all_dark = false end
        end
        if all_dark then ctx:x_mult(3, "Blackboard") end
    end })
add({ id = "sixth_sense", name = "Sixth Sense", rarity = "Uncommon",
    note = "Destroy single played 6 to create Spectral (no scoring)" })
add({ id = "constellation", name = "Constellation", rarity = "Uncommon", defaults = { xmult = 1 },
    independent = function(ctx, j) if j.state.xmult > 1 then ctx:x_mult(j.state.xmult, "Constellation") end end })
add({ id = "hiker", name = "Hiker", rarity = "Uncommon",
    on_scored = function(ctx, c) ctx:add_chips(5, "Hiker") end,
    note = "Permanently adds +5 chips to scored cards (per-hand bonus shown)" })
add({ id = "card_sharp", name = "Card Sharp", rarity = "Uncommon",
    independent = function(ctx) if ctx.config.hand_played_this_round then ctx:x_mult(3, "Card Sharp") end end })
add({ id = "madness", name = "Madness", rarity = "Uncommon", defaults = { xmult = 1 },
    independent = function(ctx, j) if j.state.xmult > 1 then ctx:x_mult(j.state.xmult, "Madness") end end })
add({ id = "seance", name = "Séance", rarity = "Uncommon",
    note = "Create Spectral on Straight Flush (generation)" })
add({ id = "vampire", name = "Vampire", rarity = "Uncommon", defaults = { xmult = 1 },
    independent = function(ctx, j) if j.state.xmult > 1 then ctx:x_mult(j.state.xmult, "Vampire") end end })
add({ id = "shortcut", name = "Shortcut", rarity = "Uncommon",
    detection = { shortcut = true }, note = "Straights can have gaps of 1" })
add({ id = "hologram", name = "Hologram", rarity = "Uncommon", defaults = { xmult = 1 },
    independent = function(ctx, j) if j.state.xmult > 1 then ctx:x_mult(j.state.xmult, "Hologram") end end })
add({ id = "vagabond", name = "Vagabond", rarity = "Uncommon",
    note = "Create Tarot if low on money (generation)" })
add({ id = "baron", name = "Baron", rarity = "Uncommon",
    on_held = function(ctx, c) if c.rank == "K" then ctx:x_mult(1.5, "Baron (held King)") end end })
add({ id = "cloud_9", name = "Cloud 9", rarity = "Uncommon", note = "Earn money per 9 in deck (economy)" })
add({ id = "rocket", name = "Rocket", rarity = "Uncommon", note = "Earn money at end of round (economy)" })
add({ id = "obelisk", name = "Obelisk", rarity = "Uncommon", defaults = { xmult = 1 },
    independent = function(ctx, j) if j.state.xmult > 1 then ctx:x_mult(j.state.xmult, "Obelisk") end end })
add({ id = "midas_mask", name = "Midas Mask", rarity = "Uncommon",
    note = "Played face cards become Gold (no scoring)" })
add({ id = "luchador", name = "Luchador", rarity = "Uncommon", note = "Disable Boss Blind (no scoring)" })
add({ id = "gift_card", name = "Gift Card", rarity = "Uncommon", note = "Adds sell value (economy)" })
add({ id = "turtle_bean", name = "Turtle Bean", rarity = "Uncommon", note = "+hand size (no scoring)" })
add({ id = "erosion", name = "Erosion", rarity = "Uncommon", defaults = { cards_below_52 = 0 },
    independent = function(ctx, j) ctx:add_mult(4 * (j.state.cards_below_52 or 0), "Erosion") end })
add({ id = "to_the_moon", name = "To the Moon", rarity = "Uncommon", note = "Interest economy" })
add({ id = "stone_joker", name = "Stone Joker", rarity = "Uncommon", defaults = { stone_in_deck = 0 },
    independent = function(ctx, j) ctx:add_chips(25 * (j.state.stone_in_deck or 0), "Stone Joker") end })
add({ id = "lucky_cat", name = "Lucky Cat", rarity = "Uncommon", defaults = { xmult = 1 },
    independent = function(ctx, j) if j.state.xmult > 1 then ctx:x_mult(j.state.xmult, "Lucky Cat") end end })
add({ id = "bull", name = "Bull", rarity = "Uncommon",
    independent = function(ctx) ctx:add_chips(2 * (ctx.config.money or 0), "Bull") end })
add({ id = "diet_cola", name = "Diet Cola", rarity = "Uncommon", note = "Sell to create Double Tag" })
add({ id = "trading_card", name = "Trading Card", rarity = "Uncommon", note = "Discard economy" })
add({ id = "flash_card", name = "Flash Card", rarity = "Uncommon", defaults = { mult = 0 },
    independent = function(ctx, j) ctx:add_mult(j.state.mult, "Flash Card") end })
add({ id = "popcorn", name = "Popcorn", rarity = "Uncommon", defaults = { mult = 20 },
    independent = function(ctx, j) ctx:add_mult(j.state.mult, "Popcorn") end })
add({ id = "spare_trousers", name = "Spare Trousers", rarity = "Uncommon", defaults = { mult = 0 },
    independent = function(ctx, j) ctx:add_mult(j.state.mult, "Spare Trousers") end })
add({ id = "ancient_joker", name = "Ancient Joker", rarity = "Uncommon", defaults = { suit = "Hearts" },
    on_scored = function(ctx, c, j) if require("engine.card").has_suit(c, j.state.suit) then ctx:x_mult(1.5, "Ancient Joker") end end })
add({ id = "ramen", name = "Ramen", rarity = "Uncommon", defaults = { xmult = 2 },
    independent = function(ctx, j) if j.state.xmult > 1 then ctx:x_mult(j.state.xmult, "Ramen") end end })
add({ id = "walkie_talkie", name = "Walkie Talkie", rarity = "Common",
    on_scored = function(ctx, c)
        if c.rank == "10" or c.rank == "4" then ctx:add_chips(10, "Walkie Talkie"); ctx:add_mult(4, "Walkie Talkie") end
    end })
add({ id = "seltzer", name = "Seltzer", rarity = "Uncommon",
    retrigger_scored = function() return 1 end, note = "Retrigger all cards (limited hands)" })
add({ id = "castle", name = "Castle", rarity = "Uncommon", defaults = { chips = 0 },
    independent = function(ctx, j) ctx:add_chips(j.state.chips, "Castle") end })
add({ id = "smiley_face", name = "Smiley Face", rarity = "Common",
    on_scored = function(ctx, c) if is_face(ctx, c) then ctx:add_mult(5, "Smiley Face") end end })
add({ id = "campfire", name = "Campfire", rarity = "Uncommon", defaults = { xmult = 1 },
    independent = function(ctx, j) if j.state.xmult > 1 then ctx:x_mult(j.state.xmult, "Campfire") end end })
add({ id = "golden_ticket", name = "Golden Ticket", rarity = "Common", note = "Gold cards earn $ (economy)" })
add({ id = "mr_bones", name = "Mr. Bones", rarity = "Uncommon", note = "Prevents death (no scoring)" })
add({ id = "acrobat", name = "Acrobat", rarity = "Uncommon",
    independent = function(ctx) if (ctx.config.hands_left or 1) <= 0 or ctx.config.last_hand then ctx:x_mult(3, "Acrobat") end end })
add({ id = "sock_and_buskin", name = "Sock and Buskin", rarity = "Uncommon",
    retrigger_scored = function(ctx, c) return is_face(ctx, c) and 1 or 0 end })
add({ id = "swashbuckler", name = "Swashbuckler", rarity = "Common",
    independent = function(ctx, self)
        local total = 0
        for _, j in ipairs(ctx.jokers) do
            if j ~= self and j.enabled ~= false then total = total + (j.sell_value or 0) end
        end
        ctx:add_mult(total, "Swashbuckler")
    end })
add({ id = "troubadour", name = "Troubadour", rarity = "Uncommon", note = "+hand size, -1 hand (no scoring)" })
add({ id = "certificate", name = "Certificate", rarity = "Uncommon", note = "Adds sealed card on blind (no scoring)" })
add({ id = "smeared_joker", name = "Smeared Joker", rarity = "Uncommon",
    detection = { smeared = true }, note = "Hearts=Diamonds, Spades=Clubs for flushes" })
add({ id = "throwback", name = "Throwback", rarity = "Uncommon", defaults = { xmult = 1 },
    independent = function(ctx, j) if j.state.xmult > 1 then ctx:x_mult(j.state.xmult, "Throwback") end end })
add({ id = "hanging_chad", name = "Hanging Chad", rarity = "Common",
    retrigger_scored = function(ctx, c)
        if not ctx._chad_first then ctx._chad_first = c end
        return (ctx._chad_first == c) and 2 or 0
    end })
add({ id = "rough_gem", name = "Rough Gem", rarity = "Uncommon", note = "Diamonds earn $1 (economy)" })
add({ id = "bloodstone", name = "Bloodstone", rarity = "Uncommon",
    on_scored = function(ctx, c, j)
        if require("engine.card").has_suit(c, "Hearts") and (j.state == nil or j.state.trigger ~= false) then
            ctx:x_mult(1.5, "Bloodstone")
        end
    end, defaults = { trigger = true } })
add({ id = "arrowhead", name = "Arrowhead", rarity = "Uncommon",
    on_scored = function(ctx, c) if require("engine.card").has_suit(c, "Spades") then ctx:add_chips(50, "Arrowhead") end end })
add({ id = "onyx_agate", name = "Onyx Agate", rarity = "Uncommon",
    on_scored = function(ctx, c) if require("engine.card").has_suit(c, "Clubs") then ctx:add_mult(7, "Onyx Agate") end end })
add({ id = "glass_joker", name = "Glass Joker", rarity = "Uncommon", defaults = { xmult = 1 },
    independent = function(ctx, j) if j.state.xmult > 1 then ctx:x_mult(j.state.xmult, "Glass Joker") end end })
add({ id = "showman", name = "Showman", rarity = "Uncommon", note = "Allows duplicate cards in shop (no scoring)" })
add({ id = "flower_pot", name = "Flower Pot", rarity = "Uncommon",
    independent = function(ctx)
        local suits = { "Spades", "Hearts", "Clubs", "Diamonds" }
        for _, s in ipairs(suits) do
            if Q.count_suit(ctx.scoring_cards, s) == 0 then return end
        end
        ctx:x_mult(3, "Flower Pot")
    end })
add({ id = "blueprint", name = "Blueprint", rarity = "Rare",
    note = "Copies the Joker to its right (copy effect not modeled; configure directly)" })

-- ===================== RARE =====================

add({ id = "wee_joker", name = "Wee Joker", rarity = "Rare", defaults = { chips = 0 },
    independent = function(ctx, j) ctx:add_chips(j.state.chips, "Wee Joker") end })
add({ id = "merry_andy", name = "Merry Andy", rarity = "Uncommon", note = "+discards, -hand size (no scoring)" })
add({ id = "oops_all_6s", name = "Oops! All 6s", rarity = "Uncommon",
    note = "Doubles all listed probabilities (affects random toggles)" })
add({ id = "the_idol", name = "The Idol", rarity = "Uncommon", defaults = { rank = "A", suit = "Spades" },
    on_scored = function(ctx, c, j)
        if c.rank == j.state.rank and require("engine.card").has_suit(c, j.state.suit) then
            ctx:x_mult(2, "The Idol")
        end
    end })
add({ id = "seeing_double", name = "Seeing Double", rarity = "Uncommon",
    independent = function(ctx)
        local has_club = Q.count_suit(ctx.scoring_cards, "Clubs") > 0
        local has_other = false
        for _, s in ipairs({ "Spades", "Hearts", "Diamonds" }) do
            if Q.count_suit(ctx.scoring_cards, s) > 0 then has_other = true end
        end
        if has_club and has_other then ctx:x_mult(2, "Seeing Double") end
    end })
add({ id = "matador", name = "Matador", rarity = "Uncommon", note = "Earn $ on boss trigger (economy)" })
add({ id = "hit_the_road", name = "Hit the Road", rarity = "Rare", defaults = { xmult = 1 },
    independent = function(ctx, j) if j.state.xmult > 1 then ctx:x_mult(j.state.xmult, "Hit the Road") end end })
add({ id = "the_duo", name = "The Duo", rarity = "Rare",
    independent = function(ctx) if Q.hand_contains(ctx, "pair") then ctx:x_mult(2, "The Duo") end end })
add({ id = "the_trio", name = "The Trio", rarity = "Rare",
    independent = function(ctx) if Q.hand_contains(ctx, "three") then ctx:x_mult(3, "The Trio") end end })
add({ id = "the_family", name = "The Family", rarity = "Rare",
    independent = function(ctx) if Q.hand_contains(ctx, "four") then ctx:x_mult(4, "The Family") end end })
add({ id = "the_order", name = "The Order", rarity = "Rare",
    independent = function(ctx) if Q.hand_contains(ctx, "straight") then ctx:x_mult(3, "The Order") end end })
add({ id = "the_tribe", name = "The Tribe", rarity = "Rare",
    independent = function(ctx) if Q.hand_contains(ctx, "flush") then ctx:x_mult(2, "The Tribe") end end })
add({ id = "stuntman", name = "Stuntman", rarity = "Rare",
    independent = function(ctx) ctx:add_chips(250, "Stuntman") end })
add({ id = "invisible_joker", name = "Invisible Joker", rarity = "Rare",
    note = "Duplicate a Joker after 2 rounds (no scoring)" })
add({ id = "brainstorm", name = "Brainstorm", rarity = "Rare",
    note = "Copies the leftmost Joker (copy effect not modeled; configure directly)" })
add({ id = "satellite", name = "Satellite", rarity = "Uncommon", note = "Earn $ per Planet used (economy)" })
add({ id = "shoot_the_moon", name = "Shoot the Moon", rarity = "Common",
    on_held = function(ctx, c) if c.rank == "Q" then ctx:add_mult(13, "Shoot the Moon (held Queen)") end end })
add({ id = "drivers_license", name = "Driver's License", rarity = "Rare", defaults = { enough = true },
    independent = function(ctx, j) if j.state.enough then ctx:x_mult(3, "Driver's License") end end })
add({ id = "cartomancer", name = "Cartomancer", rarity = "Uncommon", note = "Create Tarot on blind (generation)" })
add({ id = "astronomer", name = "Astronomer", rarity = "Uncommon", note = "Free Planet/Celestial (economy)" })
add({ id = "burnt_joker", name = "Burnt Joker", rarity = "Rare", note = "Upgrade first discarded hand (no scoring)" })
add({ id = "bootstraps", name = "Bootstraps", rarity = "Uncommon",
    independent = function(ctx) ctx:add_mult(2 * math.floor((ctx.config.money or 0) / 5), "Bootstraps") end })

-- ===================== LEGENDARY =====================

add({ id = "canio", name = "Canio", rarity = "Legendary", defaults = { xmult = 1 },
    independent = function(ctx, j) if j.state.xmult > 1 then ctx:x_mult(j.state.xmult, "Canio") end end })
add({ id = "triboulet", name = "Triboulet", rarity = "Legendary",
    on_scored = function(ctx, c) if c.rank == "K" or c.rank == "Q" then ctx:x_mult(2, "Triboulet") end end })
add({ id = "yorick", name = "Yorick", rarity = "Legendary", defaults = { xmult = 1 },
    independent = function(ctx, j) if j.state.xmult > 1 then ctx:x_mult(j.state.xmult, "Yorick") end end })
add({ id = "chicot", name = "Chicot", rarity = "Legendary", note = "Disable Boss Blind (no scoring)" })
add({ id = "perkeo", name = "Perkeo", rarity = "Legendary", note = "Duplicate a consumable (generation)" })

-- Build lookup + ordered id list.
local by_id = {}
local order = {}
for _, d in ipairs(defs) do
    by_id[d.id] = d
    order[#order + 1] = d.id
end

return {
    defs = defs,
    by_id = by_id,
    order = order,
    -- Create a fresh instance of a joker with default state.
    instance = function(id)
        local def = by_id[id]
        if not def then error("unknown joker: " .. tostring(id)) end
        local state = {}
        if def.defaults then
            for k, v in pairs(def.defaults) do state[k] = v end
        end
        return { id = id, edition = "none", enabled = true, debuffed = false, state = state, sell_value = 0 }
    end,
}
