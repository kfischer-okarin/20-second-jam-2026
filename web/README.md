# Web build

DragonRuby's shaders do not run in web builds yet, so the web version of the game runs the same `mygame/` folder on a
runtime of its own: mruby compiled to WebAssembly, the part of DragonRuby's API that the game uses, and WebGL2 for the
drawing. `web/build` compiles the game's HLSL shaders to WebGL's GLSL, so they stay HLSL.

The game's Ruby, shaders and sounds go in unchanged. Bringing a change made in DragonRuby to the web means running
`web/build` again; only a part of the engine API that the game has not used before needs work here (see
[When the web build fails](#when-the-web-build-fails)).

## Building and running

It needs Emscripten, glslang and SPIRV-Cross (`brew install emscripten glslang spirv-cross`), plus Ruby with rake and
zip.

```sh
web/build    # web/dist/index.html with its .js, .wasm and .data, and web/dist/<gameid>-<version>-web.zip
web/serve    # serves web/dist at http://localhost:8000 (another port as the first argument)
```

- The first build downloads mruby and compiles it into `web/.cache` (about a minute); after that a build takes a few
  seconds.
- The page starts with "Click to play": browsers only allow sound after a click.
- Add `?setup=autopilot` (or `doom`, `finale`, `playing`) to the URL to start like `scripts/game reset <setup>`.
- In the browser console:
  - `dr.eval('GameCli.state')` evaluates Ruby in the game and returns the inspected result
  - `dr.pause()`, `dr.step(10)` and `dr.resume()` stop the ticks, run some, and let them run again
- F1 cycles through the render targets like in DragonRuby.

## Checking the web build

`web/check` plays a round of autopilot in headless Chrome, prints `GameCli.state` every 2 seconds, and fails when the
page reports an error or the game stops ticking. Run it after `web/build` whenever changes came over from DragonRuby.

```sh
web/check                # autopilot for 35 seconds, through the finale to the results
web/check finale 10      # another setup, for another number of seconds
```

It needs Node (from `mise.toml`) and, once, `npm install` in `web/` for Playwright. It drives the installed Google
Chrome, or Playwright's own Chromium after `npx playwright install chromium`.

## Uploading to itch.io

1. `web/build`
2. On the game's itch.io page, set *Kind of project* to *HTML* and upload `web/dist/<gameid>-<version>-web.zip`
   (`index.html` is at its root). Tick *This file will be played in the browser*.
3. Under *Embed options*, a viewport of 1280×720 fits the game exactly; at other sizes it scales with black bars.
   *Fullscreen button* is worth ticking.

The page needs WebGL2 (every current desktop browser). There are no touch controls, so phones can only watch.

## When the web build fails

- **`NoMethodError: undefined method 'it'`**: the runtime's mruby 4.0 has no `it` block parameter yet. Use `_1` or
  a named block parameter, or teach the runtime's mruby `it` (a patch in `runtime/mruby/`).
- **`NotImplementedError: ... is not implemented by the web runtime yet`** in the page: the game now uses a part of
  DragonRuby's API that the runtime lacks. Add it to `runtime/dragonruby.rb` (and to `runtime/host.js` and
  `runtime/main.c` when it draws, plays or reads something new). A `NameError` or `NoMethodError` about a DragonRuby
  constant or method means the same, for example `BLENDFACTOR_ONE` for a blend mode from `Numeric.compose_blendmode`.
- **A shader's cbuffer "has a different layout in WebGL"** from `web/build`: WebGL packs uniforms differently from HLSL
  for some layouts; declare the cbuffer's fields as `float4`s (as `guides/dragonruby-rendering.md` advises anyway).
- **Something looks different**: compare single render targets in both (F1 in each), and check the behavior below.

## How it works

| File | Role |
|---|---|
| `build` | builds mruby, copies `mygame/` without tests, compiles each `.hlsl` (HLSL → SPIR-V with glslang → GLSL ES 3.00 with SPIRV-Cross, plus a JSON file telling `host.js` how to bind it), links everything with Emscripten and zips it |
| `serve`, `check` | serve `dist/` for a browser; play it headless and report errors |
| `runtime/main.c` | runs mruby and gives the Ruby side the module `WebHost`: drawing commands into a buffer for `host.js`, `draw_sprite_6` for `draw_override`, files, input, sound |
| `runtime/dragonruby.rb` | the Ruby half of DragonRuby's API: `args`, `outputs` and render targets, `inputs`, `audio`, `GTK`, `Kernel.tick_count`, `require`, module `Main` |
| `runtime/host.js` | runs 60 ticks per second, renders each tick's commands with WebGL2, plays sounds with Web Audio, reads keyboard, mouse and gamepad |
| `runtime/shell.html` | the page around the canvas |
| `runtime/mruby/` | the mruby build configuration and the patch that makes its numbers behave like DragonRuby's |

What it reproduces from DragonRuby 7.24, found by running the same code in both and by reading the engine's Ruby
sources in its `docs/oss`:

- **Numbers:** `/` on two Integers gives a Float, also in `eval`; Integers are 64 bits wide; float literals and
  `String#to_f` give the nearest double (mruby 4.0's own parsing is sometimes a bit off: `0.95`); `Float#to_s` prints
  16 exactly rounded digits (`Math::PI.to_s` is `"3.141592653589793"`, `(9.0 * 0.95).to_s` is `"8.549999999999999"`).
- **Drawing:** render targets render in the order the tick first touches them; blend modes are SDL's (alpha blending
  stores premultiplied color, additive blending leaves alpha alone); sprite colors and alpha are truncated to whole
  numbers; `scale_quality_enum` picks nearest or linear filtering, defaulting to `scale_quality` in
  `game_metadata.txt`.
- **Shaders:** a render target's shader does not change the target. It is the fragment shader of every sprite that
  draws the target: `t0` is the target, `textures:` are `t1`, `t2`, ..., `TEXCOORD0` is the sprite's texture coordinate
  with (0, 0) at the top left, `COLOR0` its color, and the sprite's scale quality and blend mode apply.
- **Inputs:** `key_down` and `key_held` never hold the same key in one tick; WASD also count as `w_scancode`, ...; when
  both opposite directions are held, the one of the previous tick wins.
- **Sound:** a new Hash under a key of `args.audio` starts a sound, changing its `gain`, `pitch` or `paused` changes it,
  removing it stops it, and a finished sound disappears from `args.audio`.

On the same frame (the intro after 300 ticks, see below), the final image differs from DragonRuby's in about 0.05% of
its pixels. WebAssembly's math library (musl) and Apple's
disagree in the last bit for a few percent of `Math.sin`, `cos` and `atan2` results and for most of `**` with a
fractional exponent, which now and then moves a truncated color by one step, and occasionally the dithering to the
next palette color.

To compare the two yourself, run the same Ruby in both games (`scripts/game eval` and `dr.eval`), for example
`Game.current = Game.new($args); 300.times { Game.current.send(:update, 1.0 / 60, { fire: false, confirm: false,
pointer: [100.0, 140.0] }) }; Game.current.define_singleton_method(:update) { |*_| nil }`, which freezes both on the
same frame, then take screenshots of a 1280×720 window.

## Differences from DragonRuby

Things the game does not use, which the runtime does not do (yet):

- labels, and `outputs.solids`, `lines` and `borders` (Hash primitives without a `path` in `primitives` are drawn as
  solids), a shader on the screen (`outputs.shader`), `args.events`, `outputs.debug`, touch input
- blend modes from `Numeric.compose_blendmode` (`blendmode:`)
- writing files, save data, HTTP, hot reload (`$gtk.files_reloaded` is always empty)
- sound positions (`x`, `y`, `z` in `args.audio`)
- the `it` block parameter (mruby 4.0 has `_1` but not `it`)

And it differs in these:

- `rand` gives other numbers than DragonRuby's for the same seed
- an Integer overflow raises a `RangeError` instead of becoming a Float
- `{ 4 => :a }[4.0]` is `nil` (DragonRuby finds `:a`)
- `Time.now` has a resolution of a millisecond, so `update_ms` and `draw_ms` in `GameCli.state` are whole numbers
- `RUBY_VERSION` is `"4.0"`
