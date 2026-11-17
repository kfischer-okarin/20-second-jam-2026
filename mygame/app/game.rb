# Last Latte: an old man on his terrace makes one last latte while the sun goes supernova. The player pours the
# latte art against the clock of a wall of light coming across the meadow; when it arrives, he drinks it, content,
# and everything goes white.
#
# The game runs through these states, then starts over:
#   :title   his view, tilted up at a calm sky with the title and a button
#   :launch  the sun bursts, the camera tilts down to the table and the pitcher rises into the player's control
#   :play    pouring until the wave of light reaches the table (see Terrace for the scene, Pitcher for controls)
#   :settle  the pitcher settles back onto the table
#   :art     straight down onto the cup: the art glows, his hand takes the cup and lifts it out of frame
#   :face    his face, content, as white closes in from the edges
#   :white   only white and an afterimage of the art, as the title fades back in
class Game
  PLAY_SECONDS = 75.0
  # How much of the time the wave takes to cross the meadow before it reaches the table
  MEADOW_SHARE = 0.82
  TITLE_TILT = -74.0
  DURATIONS = { launch: 3.6, settle: 1.8, art: 8.0, face: 6.5, white: 6.5 }.freeze
  SOUNDS = %i[pour ambience wave supernova whoosh splash clink tick drone ending].freeze
  BUTTON = { x: 160, y: 118, w: 96, h: 17 }.freeze
  TEXT = [62, 39, 49].freeze
  LIGHT_TEXT = [255, 255, 255].freeze

  attr_reader :post, :boot_ms, :state, :state_time, :terrace
  # Pours by itself (see GameCli)
  attr_accessor :autopilot

  class << self
    attr_accessor :current
  end

  def initialize(args)
    started = Time.now.to_f
    Textures.create(args)
    @camera = Camera.new
    @post = PostProcess.new
    @frame_stats = FrameStats.new
    @sfx = Sfx.new(SOUNDS)
    @ending = Ending.new
    EndingModels.prepare
    @autopilot = nil
    @time = 0.0
    start_title
    @boot_ms = ((Time.now.to_f - started) * 1000).round
  end

  def tick(args)
    @frame_stats.measure do
      @audio = args.audio
      dt = 1.0 / 60
      @camera.update(dt)
      update(dt, args) unless @camera.frozen?
      render(args)
    end
    # The ending's models bake in the time the frame leaves, most of it while the title waits
    ModelCache.bake_some(@state == :title ? 0.008 : 0.003)
  end

  # See FrameStats
  def performance
    @frame_stats.values
  end

  # Starts pouring right away, for scripts/game reset
  def skip_to_play
    @terrace.view.tilt = 0.0
    @terrace.pitcher.take
    enter(:play)
  end

  # Jumps into the ending with a heart already poured, for scripts/game reset
  def skip_to_ending(state)
    @terrace.view.tilt = 0.0
    @terrace.light_progress = 2.0
    pour_heart
    @terrace.pitcher.put_down
    enter(state == :white ? :face : state)
    @state_time = DURATIONS[:face] - 0.5 if state == :white
  end

  private

  def start_title
    @terrace = Terrace.new
    @terrace.view.tilt = TITLE_TILT
    @hover = false
    enter(:title)
  end

  # Runs the heart autopilot's pour in fast forward
  def pour_heart
    pilot = Autopilot.new(:heart)
    @terrace.pitcher.take
    dt = 1.0 / 60
    (11.0 / dt).to_i.times do |i|
      @terrace.update(dt, pilot.controls(i * dt))
    end
  end

  def enter(state)
    @state = state
    @state_time = 0.0
    @done = {}
    send(:"enter_#{state}") if respond_to?(:"enter_#{state}", true)
  end

  def update(dt, args)
    @time += dt
    @state_time += dt
    @mouse = args.inputs.mouse
    @keyboard = args.inputs.keyboard
    send(:"update_#{@state}", dt, args.inputs)
    @terrace.update(dt, controls) unless @state == :face
    update_sound
    update_cursor
  end

  # The pitcher is the cursor while pouring
  def update_cursor
    hide = @state == :play && !@autopilot
    return if hide == @cursor_hidden

    hide ? $gtk.hide_cursor : $gtk.show_cursor
    @cursor_hidden = hide
  end

  # --- Title ---------------------------------------------------------------------------------------------------

  def update_title(_dt, inputs)
    @terrace.view.tilt = TITLE_TILT
    over = over_button?(inputs.mouse)
    @sfx.play(@audio, :tick, gain: 0.25) if over && !@hover
    @hover = over
    enter(:launch) if (inputs.mouse.click && over) || start_pressed?(inputs)
  end

  def start_pressed?(inputs)
    keyboard = inputs.keyboard.key_down
    controller = inputs.controller_one.key_down
    keyboard.enter || keyboard.space || controller.a || controller.start
  end

  def over_button?(mouse)
    x = mouse.x / PostProcess::SCALE.to_f
    y = mouse.y / PostProcess::SCALE.to_f
    (x - BUTTON[:x]).abs < BUTTON[:w] * 0.5 && (y - BUTTON[:y]).abs < BUTTON[:h] * 0.5
  end

  # --- Launch: the sun bursts ----------------------------------------------------------------------------------

  def enter_launch
    sun_x = 160.0
    sun_y = @terrace.view.horizon_y + @terrace.view.tilt + World::MEADOW_DEPTH + 36.0
    @camera.flash!([1.0, 0.98, 0.9], 0.95)
    @camera.shockwave(sun_x, sun_y, speed: 160.0, strength: 3.0, life: 1.4)
    @camera.shake(0.18)
    @camera.aberrate(2.5)
    @sfx.play(@audio, :supernova, gain: 0.9)
    @tilt_from = @terrace.view.tilt
  end

  def update_launch(_dt, _inputs)
    t = @state_time
    @terrace.light_progress = [@terrace.light_progress, (t / 3.0).clamp(0.0, 1.0) * 0.02].max
    tilt = ((t - 0.7) / 2.4).clamp(0.0, 1.0)
    @terrace.view.tilt = @tilt_from * (1.0 - smootherstep(tilt))
    once(:whoosh) { @sfx.play(@audio, :whoosh, gain: 0.5) } if t >= 0.8
    once(:take) { @terrace.pitcher.take } if t > 1.4 && !@terrace.pitcher.held?
    enter(:play) if t >= DURATIONS[:launch] && @terrace.pitcher.held?
  end

  # Runs the block the first time it is called for this event in the current state
  def once(event)
    return if @done[event]

    @done[event] = true
    yield
  end

  # --- Play ------------------------------------------------------------------------------------------------------

  # The wave crosses the meadow during most of the time and the table during the last seconds
  def update_play(_dt, _inputs)
    progress = @state_time / PLAY_SECONDS
    @terrace.light_progress = if progress < MEADOW_SHARE
                                0.02 + (progress / MEADOW_SHARE * 0.98)
                              else
                                1.0 + ((progress - MEADOW_SHARE) / (1.0 - MEADOW_SHARE))
                              end
    enter(:settle) if progress >= 1.0
  end

  # What the player does with the pitcher: aim on the coffee's plane, height, tilt and pouring
  def controls
    return @autopilot.controls(@state_time) if @autopilot && @state == :play

    mouse = @mouse
    keyboard = @keyboard
    x, z = @terrace.view.unproject(mouse.x / PostProcess::SCALE.to_f, mouse.y / PostProcess::SCALE.to_f,
                                   @terrace.surface_y)
    raise = axis(keyboard, %i[w up], %i[s down])
    raise += mouse.wheel.y * 6.0 if mouse.wheel
    {
      aim_x: x, aim_z: z, raise: raise.clamp(-3.0, 3.0), tip: axis(keyboard, %i[d right], %i[a left]),
      pour: mouse.button_left
    }
  end

  def axis(keyboard, positive, negative)
    (positive.any? { |key| keyboard.key_held.send(key) } ? 1.0 : 0.0) -
      (negative.any? { |key| keyboard.key_held.send(key) } ? 1.0 : 0.0)
  end

  # --- Settle: time is up --------------------------------------------------------------------------------------

  def enter_settle
    @terrace.pitcher.put_down
  end

  def update_settle(_dt, _inputs)
    @terrace.light_progress = 2.0 + (@state_time * 0.04)
    once(:clink) { @sfx.play(@audio, :clink, gain: 0.35, pitch: 0.8) } if @terrace.pitcher.mode == :rest
    enter(:art) if @state_time >= DURATIONS[:settle]
  end

  # --- The ending ------------------------------------------------------------------------------------------------

  def enter_art
    @ending.start_art(@terrace)
    @sfx.play(@audio, :ending, gain: 0.7)
  end

  def update_art(dt, _inputs)
    @ending.update_art(@terrace, @state_time, dt) do |sound|
      @sfx.play(@audio, sound, gain: 0.4)
    end
    enter(:face) if @state_time >= DURATIONS[:art]
  end

  def enter_face
    @ending.start_face
  end

  def update_face(dt, _inputs)
    @ending.update_face(@state_time, dt)
    enter(:white) if @state_time >= DURATIONS[:face]
  end

  # The title comes back with a fresh coffee, while the art lingers as an afterimage
  def enter_white
    @art_pixels = @terrace.coffee.pixels.dup
    start_title
    @state = :white
    @state_time = 0.0
  end

  def update_white(_dt, _inputs)
    enter(:title) if @state_time >= DURATIONS[:white]
  end

  # --- Sound -----------------------------------------------------------------------------------------------------

  # The loops follow the story: the calm terrace around the title, music and the rushing light while pouring
  def update_sound
    @sfx.play_loop(@audio, :ambience, ambience_gain)
    @sfx.play_loop(@audio, :drone, drone_gain)
    @sfx.play_loop(@audio, :wave, wave_gain)
    @sfx.play_loop(@audio, :pour, @state == :play ? @terrace.pour_gain * 0.7 : 0.0)
    return unless @terrace.splash_sound > 0.004 && rand < 0.25

    @sfx.play(@audio, :splash, gain: 0.35, pitch: 0.85 + (rand * 0.3))
  end

  def ambience_gain
    case @state
    when :title then 0.55
    when :white then 0.55 * (@state_time / DURATIONS[:white]).clamp(0.0, 1.0)
    else 0.0
    end
  end

  def drone_gain
    case @state
    when :launch then 0.32 * (@state_time / 3.0).clamp(0.0, 1.0)
    when :play, :settle then 0.32
    else 0.0
    end
  end

  def wave_gain
    case @state
    when :launch then 0.1
    when :play then 0.1 + (((@state_time / PLAY_SECONDS)**2) * 0.75)
    when :settle then 0.85
    else 0.0
    end
  end

  # --- Rendering -------------------------------------------------------------------------------------------------

  def render(args)
    batches = if @state == :face
                @ending.face_batches
              else
                @terrace.render(args)
              end
    batches += @ending.hand_batches if @state == :art
    render_afterimage(args) if @state == :white
    grade
    @post.render(args.outputs, batches: batches, camera: @camera, hud: hud, waves: @camera.wave_uniforms,
                               time: @time)
  end

  # Post-processing follows the light: more bloom and exposure as the wave comes, white at the end
  def grade
    post = @post
    progress = @terrace.light_progress
    post.flash = @camera.flash
    post.flash_color = @camera.flash_color
    post.aberration = @camera.aberration
    post.background_color = World.sky_color(1.0, progress * 0.5).map(&:round)
    post.bloom = 0.75 + (progress * 0.25)
    post.bright_threshold = 0.78 - (progress * 0.06)
    post.vignette = 0.3
    post.exposure = 1.0 + (progress * 0.08)
    post.saturation = 1.08
    # A clean look: every pixel takes its nearest palette color, and objects have no outlines
    post.dither = 0.0
    post.outline = 0.0
    post.shadow_tint = 0.35
    post.shadow_tint_color = [0.08, 0.04, 0.12]
    post.veil_color = [1.0, 1.0, 0.98]
    post.veil = veil
    post.veil_softness = 0.35
    @ending.grade(post, @state, @state_time) if %i[art face].include?(@state)
  end

  def veil
    case @state
    when :face then (@state_time / (DURATIONS[:face] - 0.8)).clamp(0.0, 1.0)
    when :white then 1.0 - smootherstep(((@state_time - 2.0) / 4.0).clamp(0.0, 1.0))
    when :art then smootherstep(((@state_time - 6.8) / 1.2).clamp(0.0, 1.0))
    else 0.0
    end
  end

  def smootherstep(t)
    t * t * t * ((t * ((t * 6.0) - 15.0)) + 10.0)
  end

  # --- HUD -------------------------------------------------------------------------------------------------------

  def hud
    primitives = []
    title_hud(primitives) if %i[title launch white].include?(@state)
    hint_hud(primitives) if @state == :play
    afterimage(primitives) if @state == :white
    primitives
  end

  def title_hud(primitives)
    alpha = case @state
            when :title then 1.0
            when :launch then (1.0 - (@state_time * 3.0)).clamp(0.0, 1.0)
            else ((@state_time - 3.0) / 2.5).clamp(0.0, 1.0)
            end
    return if alpha <= 0.0

    y = 140 + @terrace.view.tilt - TITLE_TILT
    halo(primitives, 160, y + 10, 220, 60, alpha * 0.5)
    PixelFont.draw(primitives, 'LAST LATTE', 160, y, scale: 3, color: TEXT, align: :center, alpha: 255 * alpha)
    button(primitives, alpha)
  end

  def halo(primitives, x, y, w, h, alpha)
    primitives << { x: x - (w * 0.5), y: y - (h * 0.5), w: w, h: h, path: :splat, r: 255, g: 250, b: 236,
                    a: 255 * alpha }
  end

  def button(primitives, alpha)
    lift = @hover ? 1 : 0
    x = BUTTON[:x] - (BUTTON[:w] * 0.5)
    y = BUTTON[:y] - (BUTTON[:h] * 0.5) + lift + @terrace.view.tilt - TITLE_TILT
    fill = @hover ? [255, 250, 236] : [234, 212, 170]
    primitives << { x: x + 1, y: y, w: BUTTON[:w] - 2, h: BUTTON[:h], path: :pixel, r: TEXT[0], g: TEXT[1],
                    b: TEXT[2], a: 255 * alpha }
    primitives << { x: x, y: y + 1, w: BUTTON[:w], h: BUTTON[:h] - 2, path: :pixel, r: TEXT[0], g: TEXT[1],
                    b: TEXT[2], a: 255 * alpha }
    primitives << { x: x + 1, y: y + 1, w: BUTTON[:w] - 2, h: BUTTON[:h] - 2, path: :pixel, r: fill[0], g: fill[1],
                    b: fill[2], a: 255 * alpha }
    PixelFont.draw(primitives, 'HAVE A LATTE', BUTTON[:x], y + 5, color: TEXT, align: :center, alpha: 255 * alpha)
  end

  def hint_hud(primitives)
    alpha = (1.0 - ((@state_time - 7.0) / 2.0)).clamp(0.0, 1.0) * (@state_time / 0.8).clamp(0.0, 1.0)
    return if alpha <= 0.0 || @autopilot

    text = 'MOUSE AIM  HOLD CLICK POUR  W/S HEIGHT  A/D TILT'
    PixelFont.draw(primitives, text, 160, 4, color: LIGHT_TEXT, align: :center, alpha: 255 * alpha,
                                             outline: TEXT)
  end

  # The art burnt into the eye, fading as the title comes back
  def afterimage(primitives)
    alpha = (1.0 - (@state_time / DURATIONS[:white])).clamp(0.0, 1.0)**1.5
    return if alpha <= 0.0 || !@art_pixels

    size = 150.0
    primitives << { x: 160 - (size * 0.5), y: 40 - (size * 0.5), w: size, h: size, path: :rt_afterimage,
                    a: 255 * alpha }
  end

  # The art's grid as it was when he drank, through the afterimage shader. Must come before the HUD's target.
  def render_afterimage(args)
    return unless @art_pixels

    n = CoffeeSurface::N
    pixels = args.pixel_array(:art_field)
    pixels.w = n
    pixels.h = n
    pixels.pixels = @art_pixels
    target = args.outputs[:rt_afterimage]
    target.set w: n, h: n, background_color: [0, 0, 0, 0]
    target.primitives << { x: 0, y: 0, w: n, h: n, path: :art_field, blendmode_enum: 0 }
    target.shader = { path: 'shaders/afterimage.frag.hlsl',
                      uniforms: [{ type: :float, value: CoffeeSurface::RADIUS_CELLS / n }] }
  end
end
