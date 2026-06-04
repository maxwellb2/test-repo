# LuaJIT Performance Sandbox

A self-contained Love2D demo that shows how much LuaJIT matters when Lua code is doing heavy numeric work.

This project runs a 2D gravity particle field in a single `main.lua` file. Each frame, every particle computes its gravitational pull against every other particle. With the default `2,000` particles, that is roughly `4,000,000` pair checks per frame before anything is drawn.

## Why This Demo Works

The simulation is intentionally built around an `O(N^2)` physics loop:

```lua
for i = 1, particle_count do
    for j = 1, particle_count do
        -- gravity calculation
    end
end
```

That makes the CPU math loop the main bottleneck. Rendering is kept simple by drawing particles as batched points, so the FPS change you see is primarily from Lua execution speed, not graphics overhead.

LuaJIT is a strong fit for this workload because the hot path repeats the same numeric operations millions of times:

- table reads for `x`, `y`, `vx`, and `vy`
- arithmetic on numbers
- `math.sqrt`
- tight nested loops
- repeated velocity updates

When LuaJIT is ON, its compiler can optimize this hot loop after it runs enough times. When LuaJIT is OFF, the same workload runs through the interpreter. The result is a clear, visible FPS difference from the exact same source code.

## What You Should See

Start the demo with LuaJIT ON. At `2,000` particles, the HUD should show a much higher FPS than when LuaJIT is toggled OFF.

Press `Space` to switch to interpreted mode. The particle field continues running, but the frame rate should drop sharply because the app is still doing millions of gravity calculations each frame without JIT compilation.

Use the particle controls to make the difference more obvious:

- `Up Arrow`: add `500` particles
- `Down Arrow`: remove `500` particles, down to a minimum of `500`
- `Space`: toggle LuaJIT ON/OFF

Increasing the count makes the workload grow quickly. For example:

- `500` particles: about `250,000` pair checks per frame
- `2,000` particles: about `4,000,000` pair checks per frame
- `3,000` particles: about `9,000,000` pair checks per frame

Because the work grows quadratically, every particle increase puts much more pressure on the Lua runtime. That is why LuaJIT's benefit is especially easy to see here.

## Running The Demo

Install Love2D, then run this folder:

```sh
love .
```

The window title should be `LuaJIT Performance Sandbox`. The HUD in the top-left corner shows:

- current FPS
- current particle count
- current LuaJIT state: `ON (Compiled)` or `OFF (Interpreted)`

## Why LuaJIT Is A Good Choice Here

Lua is excellent for gameplay and simulation code because it is small, simple, and easy to iterate on. LuaJIT keeps those benefits while making tight numeric loops dramatically faster on supported desktop Love2D builds.

For this demo, LuaJIT is valuable because it lets you keep the entire simulation in straightforward Lua while still pushing an expensive real-time workload. You can toggle the compiler at runtime and immediately compare compiled vs interpreted execution under the same physics, same particle count, and same renderer.

That makes the project a practical benchmark, not just a visual toy: it demonstrates where LuaJIT shines most clearly, in repeated hot loops with stable numeric behavior.
