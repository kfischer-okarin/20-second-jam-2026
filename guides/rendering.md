# Rendering

How the engine turns SDF models into pixels, and the rules that decide whether a visual change works.

## From model to pixels

1. At startup, models are built from signed distance functions and baked into splats:
   - `SdfBaker` (`mygame/app/render/sdf_baker.rb`) does this for models made of SDF parts
   - A model that SDF parts do not suit can be baked by code of its own, with `Rng.at` and `Noise3` for randomness that is the same on every run
   - A `SplatModel` stores every splat's position, normal, albedo, emission, size and group in parallel arrays
2. Every frame:
   - `SplatRenderer.render` turns each model's splats towards the viewer, lights them and writes them into a `SplatBatch` as gaussian ellipses. Each ellipse is a disc lying on the surface, squashed along its projected normal.
   - `Particles` and anything else made of plain splats (a background, bullets) write splats into batches of their own.
3. `PostProcess#render` (`mygame/app/render/post_process.rb`) sends every batch to the render target of its layer, all at 320×180. For the bloom, `rt_bright` holds the solid layer at half that size, and its shader, the bright pass, keeps what is brighter than 0.76 in the solid and glow layers together. A render target's shader runs wherever the target is drawn (see `dragonruby-rendering.md`), so the bright pass runs while `rt_bright` is drawn into the 80×45 `rt_blur1`; `rt_blur2` and `rt_blur3` blur it further.
4. `mygame/shaders/post.frag.hlsl` combines the layers into the final image, pixel by pixel:
   1. shockwave distortion
   2. chromatic aberration (the red and blue channels sampled a few pixels apart)
   3. alpha test and outlines
   4. glow
   5. bloom
   6. flash
   7. grading: saturation 1.1, and `PostProcess#shadow_tint_color` added to dark tones as much as `shadow_tint` says
   8. vignette
   9. HUD
   10. ordered dithering into the palette
5. The result is scaled 4× with nearest neighbour filtering.

There is no depth buffer.
- The layers stack in a fixed order: background, solid (with outlines), glow added on top, HUD. A glowing thing is never hidden behind a solid one.
- Within a layer, batches draw in the order the game passes them to `PostProcess#render`, and a model's splats in the order of its parts (later parts on top).

## Layers

A `SplatBatch` is created for a layer, and the layer sets how it blends:

| Layer | Blending | Result |
|---|---|---|
| `:background` | alpha | behind everything, soft edges survive (nebula, dim stars) |
| `:solid` | alpha, then alpha tested at 0.25 | opaque pixels with a dark one pixel outline. Cannot be translucent: low alpha only erodes the silhouette in hard steps |
| `:glow` | additive | light: fades by getting darker, never darkens what is behind it, no outline, feeds the bloom |
| HUD | Hash primitives in `rt_ui` | drawn over everything after grading; only shakes where the game adds the camera offset itself |

Every batch follows the camera shake through `PostProcess`, scaled by its `parallax` (a distant sky might use 0.3). An owner's own displacement goes into `shift_x`/`shift_y`, such as a tremor of the thing it draws.

Light is not part of a layer: `SplatRenderer` lights model splats in whatever layer they go to, while particles and other plain splats bring their colors as they are.

Translucent things:
- If they may glow (energy, ghosts, jellyfish), put them in `:glow`: render the model into a batch of the glow layer.
- A model in `:glow` is the sum of its overlapping splats. With `size` at 3× `spacing` that adds up to roughly 2 to 3 times the albedo, so give it dark colors and check `debug_view = :rt_glow`. Its back faces stay culled, it has no outline, and its dark sides show the background instead of shade.
- Translucent things that do not glow need a new layer. That means changes in several places, which have to stay in sync:
  - `SplatBatch::BLENDMODES`
  - a target in `PostProcess#render` and `final_pass`'s `textures:`
  - a `register(tN)`/`register(sN)` pair and the blending in the shader's `composite`
  - `PostProcess::DEBUG_VIEWS`

## Color

- Every on-screen pixel ends up as one of the 32 ENDESGA colors, listed as `PALETTE` in `post.frag.hlsl`, with a 4×4 Bayer dither between the two nearest. Small hue changes can vanish or jump to another palette color. Compare `debug_view = :rt_solid` (colors before the post shader) with the final image.
  - Another palette goes into `PALETTE`. `OUTLINE` next to it (the color of the outlines) and `PostProcess#background_color` are best taken from the palette too, or they come out dithered.
- A solid splat's color is its albedo times its light, plus its emission.
  - The light (`Lighting`) is ambient + a sun + a rim light on edges, all chosen by the game.
  - Ambient and rim are shared by everything, so they tint every albedo.
  - Emission adds `albedo × emission × glow`, independent of light.
- The bloom starts at a brightness of 0.76 (`PostProcess#bright_threshold`, brightest channel) and grows with the square of how far a pixel is above it. Keep lit surfaces below it and things that should glow well above it.
  - The bright pass runs at 80×45, a quarter of the scene's resolution. Each of its pixels averages a 4×4 block of the solid layer, but only the middle 2×2 of that block of the glow layer.
  - So something solid only 2 or 3 pixels wide is averaged with its dark surroundings first and has to be very bright to bloom, and a glow only 1 pixel wide counts only while it is in the middle of its block.
  - `debug_view = :rt_bright` runs the bright pass at the screen's resolution and shows more than reaches the bloom; `:rt_blur1` shows what does.
- HUD colors taken from the palette come through unchanged.

## Positions

| Space | Units and axes | Where |
|---|---|---|
| Scene | 320×180 pixels, y up | game logic, batches |
| Model | x right, y up, z towards the viewer | SDF parts, `Rot3` |
| Shader | pixels from the top left, y down | `PostProcess#uniforms` converts shockwaves |
| Window and screenshots | 1280×720, y up (4× scene) | mouse input (divided by `PostProcess::SCALE`), `scripts/game pixel` |

## Models

- A model is a list of parts. Each part has an SDF lambda, a color, and optionally an emission, a smooth blend and a subtraction (see the `SdfBaker` header; the primitives are in `Sdf`).
- `SdfBaker.bake` options:
  - `spacing` is the distance between splats, `size` their diameter. Keep `size` at about 3× `spacing` so neighbours overlap into a closed surface.
  - `bounds` must contain the whole model.
- Baking takes 100 to 400 ms per model at startup, so bake in `ModelCache.fetch`, which keeps models until code changes. The `scale` of `SplatRenderer.render` enlarges a model on screen without adding splats.

## Juice

- `Camera`: `shake(trauma)`, `kick(dx, dy)`, `freeze(frames)` (hit-stop), `flash!(color, amount)`, `aberrate(pixels)`, `slow_motion(scale, seconds)`, `shockwave(x, y, ...)` (a distortion ring in the post shader; only the 4 strongest at a time are drawn). The game copies its flash and aberration into `PostProcess` every frame.
- `Particles`: a `ramp:` of colors (glow layer) or a `color:` that cools to the ember color (solid layer), with drag, streaks along their velocity, and gravity towards an attractor.
- Point lights (`Lighting#add_point`) cost time for every lit splat; see `performance.md`.

## Shaders and render targets

How DragonRuby's render targets, blend modes and shaders behave is in `guides/dragonruby-rendering.md`. What the engine builds on it:

- The shaders are `mygame/shaders/post.frag.hlsl` and `bright_pass.frag.hlsl`. Their uniforms are built in `PostProcess#uniforms` and `PostProcess#bright_pass`, in the order of each shader's `cbuffer`.
- The solid layer is stored premultiplied, so the post shader divides its RGB by its alpha.
- The glow layer is drawn additively, so its alpha is 0. Both shaders read it as a texture; drawing `rt_glow` into another target would add nothing.
- `SplatBatch` draws through `draw_override`, which the engine may deprecate; nothing else depends on it.
- Screenshots are 1280×720, also on high DPI displays.

## Checking a visual change

1. `scripts/game start`, then `scripts/game reset <setup>` with a setup from `mygame/app/game_cli.rb`.
2. `scripts/game screenshot <name>`, and look at the image.
3. Look at single layers with `debug_view`. It stays set across saves and resets, so set it back to `:rt_final` afterwards.
4. `scripts/game pixel <name> x,y` reads colors in window coordinates.
5. When it looks right, check `scripts/game state` for the frame time (see `performance.md`).
