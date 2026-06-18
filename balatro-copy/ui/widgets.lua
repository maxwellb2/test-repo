-- Minimal immediate-mode widget helpers for the LOVE UI. A single pending click
-- is captured on mousepressed and "consumed" by the first widget it hits during
-- draw, which keeps interaction logic inline with rendering.

local W = {}

W.click = nil          -- { x, y, button }
W.scroll_dy = 0        -- wheel delta accumulated this frame
W.hover = { x = 0, y = 0 }

local palette = {
    bg        = { 0.07, 0.08, 0.12 },
    panel     = { 0.12, 0.13, 0.18 },
    panel2    = { 0.16, 0.17, 0.23 },
    accent    = { 0.45, 0.30, 0.85 },
    accent2   = { 0.05, 0.65, 0.70 },
    chip      = { 0.30, 0.55, 0.95 },
    mult      = { 0.95, 0.35, 0.35 },
    money     = { 0.95, 0.80, 0.25 },
    text      = { 0.92, 0.93, 0.97 },
    dim       = { 0.60, 0.63, 0.72 },
    good      = { 0.45, 0.85, 0.45 },
    suit_red  = { 0.92, 0.30, 0.34 },
    suit_dark = { 0.85, 0.87, 0.95 },
}
W.palette = palette

function W.begin_frame()
    W.hover.x, W.hover.y = love.mouse.getPosition()
end

function W.end_frame()
    W.click = nil
    W.scroll_dy = 0
end

local function inside(x, y, w, h, px, py)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

function W.is_hovered(x, y, w, h)
    return inside(x, y, w, h, W.hover.x, W.hover.y)
end

-- Returns the mouse button used if this rect was clicked (consuming the click).
function W.clicked(x, y, w, h)
    if W.click and inside(x, y, w, h, W.click.x, W.click.y) then
        local b = W.click.button
        W.click = nil
        return b
    end
    return nil
end

function W.set_color(c, a)
    love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

function W.rect(mode, x, y, w, h, color, a, radius)
    W.set_color(color, a)
    love.graphics.rectangle(mode, x, y, w, h, radius or 4, radius or 4)
end

function W.text(str, x, y, color, align, wrap)
    W.set_color(color or palette.text)
    if align or wrap then
        love.graphics.printf(str, x, y, wrap or 400, align or "left")
    else
        love.graphics.print(str, x, y)
    end
end

-- A clickable button. Returns true if left-clicked.
function W.button(x, y, w, h, label, opts)
    opts = opts or {}
    local hovered = W.is_hovered(x, y, w, h)
    local bg = opts.color or (opts.active and palette.accent or palette.panel2)
    W.rect("fill", x, y, w, h, bg, hovered and 1 or 0.9)
    if hovered then
        W.rect("line", x, y, w, h, palette.accent2, 0.8)
    end
    W.set_color(opts.text_color or palette.text)
    love.graphics.printf(label, x, y + (h - 14) / 2, w, "center")
    local b = W.clicked(x, y, w, h)
    if b == 1 then return true end
    if b == 2 and opts.on_right then opts.on_right() end
    return false
end

-- A label that cycles a value list on left/right click. Returns the new value.
function W.cycler(x, y, w, h, label, value, list)
    local hovered = W.is_hovered(x, y, w, h)
    W.rect("fill", x, y, w, h, palette.panel2, hovered and 1 or 0.85)
    W.set_color(palette.dim)
    love.graphics.print(label, x + 4, y + 1)
    W.set_color(palette.text)
    love.graphics.printf(tostring(value), x, y + h - 16, w - 4, "right")
    local b = W.clicked(x, y, w, h)
    if b then
        local idx = 1
        for i, v in ipairs(list) do if v == value then idx = i break end end
        if b == 1 then idx = idx % #list + 1 else idx = (idx - 2) % #list + 1 end
        return list[idx]
    end
    return value
end

return W
