# Hilbert ring

A single closed cycle threaded along a 3D Hilbert curve, rendered with
[`ngraph.pixel`](https://github.com/anvaka/ngraph.pixel).

Every node has exactly two neighbours. There are no dangling vertices. The
curve fills space evenly, so you can push the node count far past what a
force-directed layout would survive.

## Defaults

| | |
| --- | --- |
| Order | 6 |
| Nodes | 262 144 |
| Edges | 262 144 (one cycle) |
| Degree | exactly 2 |

That sits around 200 MB of JS heap plus ~80 MB of GPU buffers on a typical
laptop. Order 7 (2 097 152 nodes) is reachable via the URL but needs well over
a gigabyte.

## Run

```bash
npm install
npm test
npm run build
npm start
```

Open http://localhost:8080 and click the canvas so keyboard controls work.

## Controls

- `WASD` — move
- `R` / `F` — up / down
- drag — look
- `Q` / `E` — roll

## Tuning

Override any setting from the query string:

```
http://localhost:8080/?order=5
http://localhost:8080/?order=6&spacing=14&size=8
http://localhost:8080/?order=7&count=1000000&spacing=8&size=6
```

| Param | Meaning | Default |
| --- | --- | --- |
| `order` | Hilbert order (cube side `2^order`) | `6` |
| `count` | Nodes to place (`<= 8^order`) | full cube |
| `spacing` | World distance between neighbours | scales with order |
| `size` | Point size | scales with count |

## Why this shape

A cycle is the densest connected graph that still obeys "at most two edges per
node". Laying that cycle along a Hilbert curve keeps consecutive nodes one cell
apart and keeps nearby indices nearby in space, which means the viewing volume
fills uniformly instead of collapsing into a tangled ball. Positions are
precomputed and the force layout is skipped entirely, so the renderer uploads
buffers once and then just draws.
