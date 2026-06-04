-- LuaJIT Performance Sandbox
-- A deliberately CPU-heavy Love2D particle field for comparing LuaJIT ON vs OFF.

local particles = {}
local jit_enabled = true
local particle_count = 2000

local gravity = 0.1
local softening = 100
local batch_points = {}

local function add_particle(width, height)
    -- Particle tables intentionally contain exactly these four simulation fields.
    particles[#particles + 1] = {
        x = love.math.random() * width,
        y = love.math.random() * height,
        vx = 0,
        vy = 0,
    }
end

local function add_particles(amount)
    local width = love.graphics.getWidth()
    local height = love.graphics.getHeight()

    for _ = 1, amount do
        add_particle(width, height)
    end
end

local function trim_particles(target_count)
    for i = #particles, target_count + 1, -1 do
        particles[i] = nil
    end
end

function love.load()
    love.window.setTitle("LuaJIT Performance Sandbox")

    -- Start with LuaJIT enabled so the HUD state and compiler state match.
    jit.on()

    add_particles(particle_count)
end

function love.update(dt)
    local width = love.graphics.getWidth()
    local height = love.graphics.getHeight()
    local sqrt = math.sqrt
    local count = particle_count

    -- This all-pairs gravity pass is the intentional O(N^2) CPU bottleneck.
    for i = 1, count do
        local p_i = particles[i]

        for j = 1, count do
            if i ~= j then
                local p_j = particles[j]
                local dx = p_j.x - p_i.x
                local dy = p_j.y - p_i.y
                local dist_sq = (dx * dx) + (dy * dy) + softening
                local dist = sqrt(dist_sq)
                local force = gravity / dist_sq

                p_i.vx = p_i.vx + (force * dx / dist)
                p_i.vy = p_i.vy + (force * dy / dist)
            end
        end
    end

    for i = 1, count do
        local p_i = particles[i]

        p_i.x = p_i.x + p_i.vx
        p_i.y = p_i.y + p_i.vy

        -- Wrap particles around the screen to keep the field continuously populated.
        if p_i.x < 0 then
            p_i.x = p_i.x + width
        elseif p_i.x > width then
            p_i.x = p_i.x - width
        end

        if p_i.y < 0 then
            p_i.y = p_i.y + height
        elseif p_i.y > height then
            p_i.y = p_i.y - height
        end
    end
end

function love.draw()
    love.graphics.clear(0.05, 0.05, 0.1)

    -- Build a flat point buffer so rendering stays cheap compared with the math loop.
    for i = 1, particle_count do
        local p = particles[i]
        local point_index = (i - 1) * 2

        batch_points[point_index + 1] = p.x
        batch_points[point_index + 2] = p.y
    end

    for i = (particle_count * 2) + 1, #batch_points do
        batch_points[i] = nil
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.points(batch_points)

    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle("fill", 10, 10, 590, 76)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("FPS: " .. love.timer.getFPS(), 20, 20)
    love.graphics.print("Particles: " .. particle_count .. " ([Up/Down Arrows] to change)", 20, 42)
    love.graphics.print(
        "LuaJIT Status: " .. (jit_enabled and "ON (Compiled)" or "OFF (Interpreted)") .. " ([Spacebar] to toggle)",
        20,
        64
    )
end

function love.keypressed(key)
    if key == "space" then
        jit_enabled = not jit_enabled

        if jit_enabled then
            jit.on()
        else
            jit.off()
        end
    elseif key == "up" then
        particle_count = particle_count + 500
        add_particles(500)
    elseif key == "down" then
        particle_count = math.max(500, particle_count - 500)
        trim_particles(particle_count)
    end
end
