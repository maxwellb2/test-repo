You are an expert Lua developer specializing in Love2D and LuaJIT optimization. Your task is to build a high-performance 2D Gravity Particle Field simulation contained entirely within a single `main.lua` file. 

The primary objective of this project is to visually demonstrate the massive performance difference when LuaJIT's compiler is toggled ON vs. OFF during an O(N²) computational workload.

Implement the code strictly according to the following specifications. Do not change the architecture, file structure, or features.

---

### 1. Project Structure & State Variables
- The entire application must reside in a single `main.lua` file.
- Maintain a global or top-level local array `particles` containing particle tables. Each particle table must have exactly four keys: `x`, `y`, `vx`, `vy`.
- Track the following application states:
  - `jit_enabled = true` (Boolean)
  - `particle_count = 2000` (Integer)

---

### 2. Physics Core (The O(N²) Bottleneck)
In the `love.update(dt)` function, implement a mutual gravitational attraction simulation. Every particle must calculate its gravitational pull relative to every other particle.
- Use a nested loop to compare every particle `i` against every particle `j` (where `i != j`).
- **Mathematical Formula:** For a pair of particles, calculate:
  dx = p_j.x - p_i.x
  dy = p_j.y - p_i.y
  dist_sq = (dx * dx) + (dy * dy) + 100  -- 100 is a softening factor to prevent division by zero when particles overlap
  dist = math.sqrt(dist_sq)
  force = 0.1 / dist_sq  -- Adjust gravity constant 0.1 for optimal visual clustering
  
  Update velocities:
  p_i.vx = p_i.vx + (force * dx / dist)
  p_i.vy = p_i.vy + (force * dy / dist)
- **Position & Bounds Update:**
  After computing velocities, update each particle's position:
  p_i.x = p_i.x + p_i.vx
  p_i.y = p_i.y + p_i.vy
- **Screen Wrapping:** If a particle leaves the screen bounds (`0` to `love.graphics.getWidth()` and `0` to `love.graphics.getHeight()`), wrap its position to the opposite side of the screen.

---

### 3. Love2D Lifecycle Functions

#### `love.load()`
- Set the window title to "LuaJIT Performance Sandbox".
- Initialize the `particles` array up to the initial `particle_count`. 
- Randomly distribute the initial positions across the full width and height of the window. Initialize velocities `vx` and `vy` to `0`.
- Explicitly call `jit.on()` at initialization to match `jit_enabled = true`.

#### `love.update(dt)`
- Execute the Physics Core logic described in Section 2.

#### `love.draw()`
- **Background:** Clear screen to a dark color (e.g., `0.05, 0.05, 0.1`).
- **Particles:** Render each particle as a single white pixel or an incredibly small 1x1 rectangle (`love.graphics.points` or a batched draw is preferred for rendering efficiency so that rendering doesn't bottleneck the CPU before the math loop does).
- **HUD Interface (Top-Left Corner):**
  Draw a solid semi-transparent black rectangle background for readability, and print the following text using standard `love.graphics.print`:
  - Line 1: "FPS: " .. love.timer.getFPS()
  - Line 2: "Particles: " .. particle_count .. " ([Up/Down Arrows] to change)"
  - Line 3: "LuaJIT Status: " .. (jit_enabled and "ON (Compiled)" or "OFF (Interpreted)") .. " ([Spacebar] to toggle)"

---

### 4. Input Handling (`love.keypressed(key)`)
Implement the following exact keyboard controls:
- **`space`**: Toggle the `jit_enabled` boolean. If it becomes true, call `jit.on()`. If it becomes false, call `jit.off()`.
- **`up`**: Increase `particle_count` by `500`. Instantly instantiate 500 new random particles and append them to the `particles` array.
- **`down`**: Decrease `particle_count` by `500` (floor the count at a minimum of `500`). Remove the excess particles from the end of the `particles` array.

---

Ensure the code is clean, fully commented, and completely self-contained within `main.lua` without requiring any external assets or libraries.