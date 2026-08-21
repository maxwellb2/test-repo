# 10M Hilbert ring

A single closed cycle of ten million nodes threaded along a 3D Hilbert curve
and rendered directly with WebGL 2.

Every node has exactly two neighbours. There are no dangling vertices. The
curve fills space evenly, so you can push the node count far past what a
force-directed layout would survive.

## Defaults

| | |
| --- | --- |
| Order | 8 |
| Nodes | 10 000 000 |
| Edges | 10 000 000 (one cycle) |
| Degree | exactly 2 |
| Position data | 28.6 MiB |

`ngraph.graph` is intentionally bypassed at this scale. Ten million graph
objects plus the renderer's duplicate node/edge models would need roughly
6–8 GB. Instead, topology is implicit: WebGL's `LINE_LOOP` connects vertex `i`
to `i + 1` and closes the final edge. Positions are packed as three unsigned
bytes each because an order-8 curve uses coordinates 0–255.

## Run

```bash
npm install
npm test
npm run build
npm start
```

Open http://localhost:8080.

## Controls

- drag — orbit
- wheel — zoom
- `E` — toggle all ten million edges
- `P` — toggle all ten million points

## Tuning

Override any setting from the query string:

```
http://localhost:8080/?count=1000000
http://localhost:8080/?count=10000000&size=1
http://localhost:8080/?count=16777216&size=2
```

| Param | Meaning | Default |
| --- | --- | --- |
| `order` | Hilbert order (automatically large enough for count, max 8) | `8` |
| `count` | Nodes to place (max 16 777 216) | `10 000 000` |
| `size` | Point size in pixels | `2` |

## Why this shape

A cycle is the densest connected graph that still obeys "at most two edges per
node". Laying that cycle along a Hilbert curve keeps consecutive nodes one cell
apart and nearby indices nearby in space. A worker generates the packed
positions without blocking loading progress; the main thread uploads one
buffer, then two draw calls render every edge and node. Rendering happens only
when the camera changes, so the idle cost is zero.
