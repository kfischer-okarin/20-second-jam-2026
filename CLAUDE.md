# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## The game

A 20-second arcade round: a turret on the rim of a planet that explodes when the clock runs out fights off invaders, and every invader that lands takes a second off the clock. Everything is drawn as SDF models baked into gaussian splats, rendered at 320×180 and post-processed into a 32 color pixel palette.

- `mygame/app/render/` and `mygame/app/sfx.rb`: the engine, which this game is built on: SDF baking, splat drawing, lighting, particles, camera juice (shake, hit-stop, flashes, shockwaves), the render target chain behind the post shader (`mygame/shaders/`), the pixel font, frame timings, sound playback. It lives on the `engine` branch, without the game; changes that any game could use belong there.
- `mygame/app/world/`: planet, turret, invaders, spawner, scoring, effects, HUD
- `mygame/app/game.rb`: the round's flow (intro, playing, finale, results), what kills and impacts set off, and the game's light and grading
- Tuning lives in data: `Invaders::TYPES` (a new kind of invader is an entry there, unless it brings new behavior such as splitting when killed, which goes into `Game#kill`), the `Spawner` schedules, the constants at the top of `Game`
- Positions are scene pixels: 320×180, y up, the planet's center at 160, 90. The window shows them 4× larger.
- Sounds are generated: change and run `scripts/generate-sounds`, never edit `mygame/sounds/*.wav`

Seeing changes:

- Saving a game file restarts the game from its intro and bakes the models again (about a second); shader files recompile without a restart
- `scripts/game reset <setup>` with the setups in `mygame/app/game_cli.rb`: `autopilot` plays a round by itself (`scripts/game press` cannot hold fire), `doom` starts 6 seconds before the end, `finale` just before the explosion
- F1 in the game, or `scripts/game eval 'Game.current.post.debug_view = :rt_glow'`, shows a single render target until set back to `:rt_final`
- `scripts/game state` reports `update_ms`, `draw_ms`, `splats`, `frame_ms` and `peak_ms`

Read first:

- `guides/rendering.md` before changing how anything looks: colors, models, lighting, particles, render layers, shaders, post-processing
- `guides/performance.md` before writing code that runs per splat or per particle, and when the frame rate drops

## Development commands

```sh
# Run all tests (exit code 1 when a test fails or the run ends without a summary)
./run-tests

# Run a single test file (path relative to mygame/)
./run-tests tests/app/some_test.rb

# Lint (Ruby and gems come from mise.toml and the Gemfile)
bundle exec rubocop
```

The DragonRuby engine is not part of the repository: it gets copied into the repository root (see README.md), and `./dragonruby` must be there for tests and the game to run.

This game sets `shaders=true`, which needs a GPU renderer that no headless SDL video driver provides. So `./run-tests` opens a window for a moment, and `scripts/game start --headless` refuses to start; both say why. Shaders also require the DragonRuby Pro license.

## Driving the running game

`scripts/game` starts its own instance of the game in the background and controls it through DragonRuby's development web server. Run it without arguments for all commands.

```sh
scripts/game start              # opens a window and hands focus back (--headless cannot run this game's shaders)
scripts/game press right a      # controller buttons through the engine's input path
scripts/game state              # tick plus whatever GameCli.state returns
scripts/game wait-until '<ruby expression>' [seconds]
scripts/game screenshot <name>  # saves mygame/tmp/game/screenshots/<name>.png
scripts/game reset [setup]      # restarts from tick 0, then runs GameCli.setup(:setup)
scripts/game stop
```

- It only touches the instance it started. `--attach` before a command uses whatever game listens on the port instead; that is usually the user's own session, so only use it when the user asks.
- Wait on game state with `wait-until`, never with `sleep`.
- A game can define a top-level `GameCli` module with `self.state` (a Hash added to `state`) and `self.setup(name)` (named starting points for `reset`). See README.md.

## Web build

DragonRuby's shaders do not run in its web builds, so `web/` builds the game for browsers (and itch.io) on a runtime of its own: `mygame/` runs unchanged on mruby compiled to WebAssembly, with DragonRuby's API as far as the game uses it, drawing with WebGL2; the HLSL shaders are compiled to WebGL's GLSL. `web/README.md` has the details.

```sh
web/build   # web/dist/index.html and the zip to upload to itch.io
web/serve   # http://localhost:8000; ?setup=autopilot (doom, finale, playing) like scripts/game reset
web/check   # plays a round of autopilot in headless Chrome and fails on errors (npm install in web/ once)
```

- A game change needs nothing web-specific unless it uses a part of DragonRuby's API that the runtime lacks. The page then shows a `NotImplementedError` naming it, and it goes into `web/runtime/dragonruby.rb` (plus `host.js` and `main.c` for new kinds of drawing, sound or input).
- The runtime's mruby 4.0 has no `it` block parameter (`_1` works). Game code that uses `it` breaks the web build until the runtime gets it.
- The runtime imitates measured engine behavior (render target order, blend modes, shaders, color truncation, inputs, audio). When DragonRuby turns out to behave differently, change the runtime and the list in `web/README.md`.
- In the browser console, `dr.eval('GameCli.state')` evaluates Ruby in the game like `scripts/game eval`.

## Testing

`mygame/tests.rb` loads every file under `mygame/tests/` except `test_helper.rb`. Test files start with `require 'tests/test_helper'`.

`lib/spec_dsl.rb` is a small RSpec-like DSL on top of DragonRuby's test runner:

- `describe`/`context` group examples, `test`/`they` define them. `it 'name' do` is a syntax error in DragonRuby, which parses `it` as the implicit block parameter
- `before_each`, `let`, `subject`, `define_helper`; `tested_method :name` defines a `call_with(...)` helper that calls it on `subject`
- focus with `fdescribe`/`fcontext`/`ftest`/`fthey`, skip with `xdescribe`/`xcontext`/`xtest`/`xthey`
- assertions on `assert`: `equal!`, `empty!`, `includes!`, `includes_no!`, `raises!` (`lib/assertions.rb`)
- mocks: `a_mock { responding_to(:name) { always_returning value } }`, asserted with `was_called!`, `was_not_called!`, `received_call!` (`lib/mocks.rb`)

## Ruby that DragonRuby supports

DragonRuby runs mruby with `RUBY_VERSION` 3.0, and `.rubocop.yml` targets that. Checked in DragonRuby 6.58 and 7.24:

- Works: endless methods (but not with `yield`), `...` forwarding (also after leading arguments), `_1` and `it` block parameters, beginless ranges, `Hash#except`/`#slice`/`#transform_values`, `Array#filter_map`, `Enumerable#tally`, `clamp(min, max)`, `String#delete_prefix`, `Array#to_h` with a block
- Syntax errors: anonymous `&`/`*`/`**` forwarding, `{ x: }` hash shorthand, all pattern matching (`case/in`, `=>`, `x in Pattern`)
- Missing: `Array#intersect?`, `Array#sort_by!`, `Range#step`, `Hash#sum`, `Integer#digits`, `clamp(range)`, `rand(range)`, `Data`, `Struct.new(keyword_init: true)`
- Wrong without an error: `Integer#/` returns a Float (`7 / 2` is `3.5`, use `idiv`); `Hash#to_h` ignores its block and returns the hash unchanged; `send(name, *args, **{})` passes the empty hash as an extra positional argument; a keyword argument's default cannot use an earlier keyword argument (`def m(a:, b: a)` calls a method `a`); `module_function` without arguments does nothing (use `extend self`)

## Names the engine already uses

The top-level constants `Mat2`-`Mat4`, `Vec2`-`Vec4`, `Matrix`, `Geometry`, `Easing`, `Layout` and `Grid` belong to the engine (reopening `Mat3` as a module fails with "Mat3 is not a module"), and render targets cannot be named `:pixel` or `:solid`.

## Render targets, blending and shaders

Read `guides/dragonruby-rendering.md` before drawing into render targets, combining blend modes, writing shaders, or drawing thousands of sprites per frame.
