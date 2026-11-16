# Performance

A frame has 16.7 ms at 60 fps, and mruby leaves little headroom: a few thousand splats on screen fit when code that runs per splat follows the rules below.

## Measuring

`scripts/game state` reports (from `FrameStats`):

- `update_ms`: the tick (simulation plus filling the batches)
- `draw_ms` and `splats`: the engine drawing the previous frame's splats, which happens after the tick
- `frame_ms`: time between ticks; above 16.7 the game is dropping frames
- `peak_ms`: the slowest recent `update_ms + draw_ms`, decaying over a few seconds

Not measured:
- drawing the HUD's Hash sprites (6 per character with its outline)
- the render target passes
- the GPU (at 320×180 the shaders are cheap)

If `frame_ms` is high while `update_ms + draw_ms` is not, look there.

To find what made the game slower:
1. Compare the numbers at the same setup before and after the change (`git stash`, or `git bisect` with the same commands).
2. Gameplay is random, so watch them over a few seconds.

## What things cost in mruby

Measured on this machine:

| Operation | Cost |
|---|---|
| A `while` loop iteration | 0.008 µs |
| An arithmetic operation with an array read | about 0.02 µs |
| `Math.atan2` | 0.05 µs |
| A method call with a few arguments (`SplatBatch#add`) | 0.4 µs |
| Building a sprite Hash every frame | about 3 µs more per sprite than writing it into a `SplatBatch` (1,500 moving splats: 7.4 ms with Hashes, 2.5 ms with a batch) |
| One visible splat from `SplatRenderer` | about 1.5 µs to build and 0.35 µs to draw |
| Each point light | adds a distance check to every splat near it |

## Rules for code that runs per splat or per particle

They matter for loops over hundreds of elements (model splats, particles). A few dozen `SplatBatch#add` calls, like a background or bullets make, cost nothing worth saving.

- **Loop:** `while` with an index over parallel arrays (`SplatModel`, `Particles`), with everything the loop reads copied into locals first.
- **Write:** directly into `batch.data` (`SplatBatch::STRIDE` numbers per splat) and set `batch.count` at the end, instead of calling `add` per splat.
- **No allocation in the loop:** no Hashes, arrays, blocks or strings. `[a, b].max` allocates, so compare with operators; `x.positive?` is a method call, so write `x > 0.0`.
- **Directive:** these loops break the method metrics on purpose, so they start with a `# Hot loop:` comment and a `# rubocop:disable-next ...` for the cops involved.

## What already keeps the frame cheap

- **Baking:** models are baked once (`ModelCache` keeps them until code changes); never bake during play.
- **Point lights:** `Lighting#points_near` skips lights that cannot reach a model, and a light added with `except:` skips that receiver altogether.
