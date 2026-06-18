-- Test cases as a reusable module so they can run under either a standalone
-- Lua interpreter (tests/run.lua) or inside LOVE (main.lua test mode).
-- Assumes package paths are already configured by the caller.

local scoring = require("engine.scoring")
local jokers = require("engine.jokers")
local Card = require("engine.card")

local function card(rank, suit, opts)
    opts = opts or {}
    opts.rank = rank
    opts.suit = suit
    return Card.new(opts)
end

local function eval(scenario)
    return scoring.evaluate(scenario)
end

local M = {}

function M.run(emit)
    emit = emit or print
    local passed, failed = 0, 0

    local function check(name, got, want)
        if got == want then
            passed = passed + 1
            emit(string.format("  ok   %-38s = %s", name, tostring(got)))
        else
            failed = failed + 1
            emit(string.format("  FAIL %-38s got %s want %s", name, tostring(got), tostring(want)))
        end
    end

    emit("== Hand detection ==")
    do
        local r = eval({ played = { card("A", "Spades"), card("A", "Hearts"), card("K", "Clubs"), card("Q", "Diamonds"), card("J", "Spades") } })
        check("pair of aces -> Pair", r.hand, "Pair")
        check("pair of aces score", r.score, 64)
    end
    do
        local r = eval({ played = {
            card("2", "Hearts"), card("4", "Hearts"), card("6", "Hearts"),
            card("8", "Hearts"), card("10", "Hearts"),
        } })
        check("five hearts -> Flush", r.hand, "Flush")
        check("flush score", r.score, 260)
    end
    do
        local r = eval({ played = {
            card("5", "Spades"), card("6", "Hearts"), card("7", "Clubs"),
            card("8", "Diamonds"), card("9", "Spades"),
        } })
        check("straight -> Straight", r.hand, "Straight")
        check("straight score", r.score, 260)
    end
    do
        local r = eval({ played = {
            card("A", "Spades"), card("2", "Hearts"), card("3", "Clubs"),
            card("4", "Diamonds"), card("5", "Spades"),
        } })
        check("A-2-3-4-5 -> Straight", r.hand, "Straight")
    end
    do
        local r = eval({ played = {
            card("K", "Spades"), card("K", "Hearts"), card("K", "Clubs"),
            card("A", "Diamonds"), card("A", "Spades"),
        } })
        check("KKK AA -> Full House", r.hand, "Full House")
    end

    emit("== Hand levels ==")
    do
        local r = eval({
            played = { card("A", "Spades"), card("A", "Hearts") },
            levels = { Pair = 2 },
        })
        check("pair lvl2 score", r.score, 141)
    end

    emit("== Card properties ==")
    do
        local r = eval({ played = { card("A", "Spades", { enhancement = "bonus", edition = "foil" }) } })
        check("bonus+foil high card", r.score, 96)
    end
    do
        local r = eval({ played = {
            card("A", "Spades", { enhancement = "glass" }),
            card("A", "Hearts", { enhancement = "glass" }),
        } })
        check("two glass aces (Pair)", r.score, 256)
    end
    do
        local r = eval({ played = { card("A", "Spades", { enhancement = "bonus", seal = "red" }) } })
        check("red seal retrigger", r.score, 87)
    end
    do
        local r = eval({
            played = { card("K", "Spades"), card("K", "Hearts") },
            held = { card("5", "Clubs", { enhancement = "steel", location = "held" }) },
        })
        check("steel held x1.5", r.score, 90)
    end

    emit("== Jokers ==")
    do
        local r = eval({ played = { card("K", "Spades"), card("K", "Hearts") }, jokers = { jokers.instance("joker") } })
        check("Joker +4 mult", r.score, 180)
    end
    do
        local r = eval({ played = { card("K", "Spades"), card("K", "Hearts") }, jokers = { jokers.instance("the_duo") } })
        check("The Duo x2", r.score, 120)
    end
    do
        local r = eval({
            played = { card("K", "Diamonds"), card("K", "Diamonds") },
            jokers = { jokers.instance("greedy_joker") },
        })
        check("Greedy Joker +3/diamond", r.score, 240)
    end
    do
        local r = eval({
            played = { card("K", "Spades"), card("K", "Hearts") },
            jokers = { jokers.instance("joker"), jokers.instance("the_duo") },
        })
        check("Joker then Duo (order)", r.score, 360)
    end
    do
        local j = jokers.instance("joker"); j.edition = "polychrome"
        local r = eval({ played = { card("K", "Spades"), card("K", "Hearts") }, jokers = { j } })
        check("Joker poly edition", r.score, 270)
    end

    emit("== Global modifiers ==")
    do
        -- base chips 10->5, mult 2->1; two kings add 20 chips => 25 * 1 = 25
        local r = eval({ played = { card("K", "Spades"), card("K", "Hearts") }, config = { boss = "the_flint" } })
        check("The Flint halves base", r.score, 25)
    end
    do
        local r = eval({ played = { card("K", "Spades"), card("K", "Hearts") }, config = { deck = "plasma" } })
        check("Plasma deck balance+x2", r.score, 512)
    end

    emit("== Catalog ==")
    check("joker count >= 140", #jokers.defs >= 140, true)

    emit(string.format("\n%d passed, %d failed", passed, failed))
    return passed, failed
end

return M
