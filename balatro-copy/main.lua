-- LOVE entry point for Balatro Lab.
--   love balatro-copy          -> launches the interactive sandbox UI
--   love balatro-copy test     -> runs the headless test suite to the console

local function wants_test(args)
    for _, a in ipairs(args or {}) do
        if a == "test" then return true end
    end
    return false
end

local test_mode = false

function love.load(args)
    if wants_test(args) then
        test_mode = true
        local cases = require("tests.cases")
        local _, failed = cases.run(function(line) io.write(line, "\n") end)
        love.event.quit(failed == 0 and 0 or 1)
        return
    end

    local function has(name) for _, a in ipairs(args or {}) do if a == name then return true end end end
    if has("smoke") then
        test_mode = true
        local app = require("ui.app")
        local ok, err = pcall(function()
            app.load()
            app.draw()
            -- move played card 1 -> held, then render
            app.mousepressed(72, 183, 1); app.draw()
            -- focus search, type, add a stateful joker, render its state editor
            app.mousepressed(400, 470, 1); app.draw()
            app.textinput("r"); app.textinput("i"); app.textinput("d"); app.textinput("e")
            app.draw()
            app.mousepressed(397, 500, 1); app.draw()
            -- bump a joker state value and toggle edition
            app.mousepressed(700, 200, 2); app.draw()
        end)
        io.write(ok and "SMOKE OK\n" or ("SMOKE FAIL: " .. tostring(err) .. "\n"))
        love.event.quit(ok and 0 or 1)
        return
    end

    require("ui.app").load()
end

function love.update(dt)
    if test_mode then return end
    require("ui.app").update(dt)
end

function love.draw()
    if test_mode then return end
    require("ui.app").draw()
end

function love.mousepressed(x, y, button)
    if test_mode then return end
    require("ui.app").mousepressed(x, y, button)
end

function love.wheelmoved(dx, dy)
    if test_mode then return end
    require("ui.app").wheelmoved(dx, dy)
end

function love.keypressed(key)
    if test_mode then return end
    require("ui.app").keypressed(key)
end

function love.textinput(t)
    if test_mode then return end
    require("ui.app").textinput(t)
end
