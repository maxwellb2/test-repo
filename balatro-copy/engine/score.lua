-- Score accumulator + breakdown log. Jokers and cards mutate this object via
-- add_chips / add_mult / x_mult, each of which appends a human-readable entry
-- to the breakdown so every point of score is explainable.

local Score = {}
Score.__index = Score

function Score.new(chips, mult)
    return setmetatable({
        chips = chips or 0,
        mult = mult or 0,
        log = {},
    }, Score)
end

function Score:_entry(kind, amount, source)
    self.log[#self.log + 1] = {
        kind = kind,
        amount = amount,
        source = source,
        chips = self.chips,
        mult = self.mult,
    }
end

function Score:add_chips(amount, source)
    if amount == 0 then return end
    self.chips = self.chips + amount
    self:_entry("chips", amount, source)
end

function Score:add_mult(amount, source)
    if amount == 0 then return end
    self.mult = self.mult + amount
    self:_entry("mult", amount, source)
end

function Score:x_mult(factor, source)
    if factor == 1 then return end
    self.mult = self.mult * factor
    self:_entry("xmult", factor, source)
end

function Score:note(source)
    self:_entry("note", nil, source)
end

-- Render the breakdown as plain text lines.
function Score:render()
    local lines = {}
    for _, e in ipairs(self.log) do
        local desc
        if e.kind == "chips" then
            desc = string.format("+%g chips", e.amount)
        elseif e.kind == "mult" then
            desc = string.format("+%g mult", e.amount)
        elseif e.kind == "xmult" then
            desc = string.format("x%g mult", e.amount)
        else
            desc = ""
        end
        lines[#lines + 1] = string.format("%-22s %-16s => %g x %g",
            e.source or "", desc, e.chips, e.mult)
    end
    return lines
end

return Score
