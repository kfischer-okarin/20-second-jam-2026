# The last 20 seconds of a dying planet. A turret on its rim holds off invaders until the planet blows up.
# Invaders that reach the surface take a second off the clock; the final explosion's shock ring takes
# everything still flying with it, for a last chain of points.
class Game
  ROUND_TIME = 20.0
  CENTER_X = 160.0
  CENTER_Y = 90.0
  PENALTY = 1.0
  FINALE_LENGTH = 3.6
  RESTART_DELAY = 1.2
  TAU = Math::PI * 2
  SOUNDS = %i[shoot hit explode big_explode impact rumble heartbeat beep final start chain ambience].freeze

  attr_reader :mode, :mode_time, :time_left, :scoring, :penalty_flash, :post, :planet, :invaders, :boot_ms
  attr_accessor :autopilot

  class << self
    attr_accessor :current
  end

  def initialize(args)
    started = Time.now.to_f
    Textures.create(args)
    @planet = Planet.new(CENTER_X, CENTER_Y)
    @turret = Turret.new(@planet)
    @invaders = Invaders.new(@planet)
    @spawner = Spawner.new(@invaders)
    @bullets = Bullets.new
    @scoring = Scoring.new
    @background = Background.new
    @lighting = Lighting.new(sun: [-0.55, 0.62, 0.56], sun_color: [1.05, 0.95, 0.85], ambient: [0.16, 0.14, 0.26],
                             rim: [0.25, 0.32, 0.65])
    @camera = Camera.new
    @post = PostProcess.new
    @post.shadow_tint_color = [0.10, 0.0, 0.015]
    @frame_stats = FrameStats.new
    @hud = Hud.new
    @sfx = Sfx.new(SOUNDS)
    @effects = Effects.new(@camera)
    @bg_batch = SplatBatch.new(:background, parallax: 0.3)
    @sky_glow = SplatBatch.new(:glow, parallax: 0.3)
    @turret_batch = SplatBatch.new(:solid)
    @time = 0.0
    @pointer_active = true
    @autopilot = false
    start_mode(:intro)
    @boot_ms = ((Time.now.to_f - started) * 1000).round
  end

  def tick(args)
    @frame_stats.measure do
      input = read_input(args.inputs)
      @audio = args.audio
      @camera.update(1.0 / 60)
      update((1.0 / 60) * @camera.time_scale, input) unless @camera.frozen?
      render(args.outputs)
    end
  end

  # See FrameStats
  def performance
    @frame_stats.values
  end

  def start_mode(mode)
    reset_round if %i[intro playing].include?(mode)
    @mode = mode
    @mode_time = 0.0
    begin_round if mode == :playing
  end

  def doom
    case @mode
    when :intro then 0.1
    when :playing then (1.0 - (@time_left / ROUND_TIME)).clamp(0.0, 1.0)
    else 1.0
    end
  end

  # Used by GameCli to jump straight to interesting moments
  def skip_to(time_left)
    start_mode(:playing) unless @mode == :playing
    @time_left = time_left
    @spawner.skip_to(time_left)
  end

  private

  # --- Round flow -----------------------------------------------------------------------------------------

  def reset_round
    [@planet, @turret, @camera, @spawner, @scoring].each(&:reset)
    [@invaders, @effects, @bullets, @hud].each(&:clear)
    @time_left = ROUND_TIME
    @penalty_flash = 0.0
    @spray_timer = 0.6
    @last_beep_second = nil
    @collapsed = false
    @target_angle = Math::PI / 2
    @desired_aim = Math::PI / 2
  end

  def begin_round
    @spawner.opening_wave(doom)
    @hud.popup('DEFEND!', CENTER_X, CENTER_Y + 56, color: Hud::YELLOW, scale: 2, life: 1.0, rise: 8.0)
    @camera.shake(0.3)
    @camera.flash!([1.0, 0.9, 0.6], 0.25)
    play(:start, gain: 0.7)
  end

  def update(dt, input)
    @time += dt
    @mode_time += dt
    @planet.update(dt, doom)
    play(:heartbeat, gain: 0.15 + (0.6 * doom)) if @planet.beat_started? && @mode != :results
    update_turret(dt, input)
    case @mode
    when :intro then update_intro(input)
    when :playing then update_playing(dt, input)
    when :finale then update_finale
    when :results then update_results(input)
    end
    update_effects(dt)
  end

  # The turret already works on the title screen, so players can try it before they start
  def update_intro(input)
    fire_turret if input[:fire]
    start_mode(:playing) if input[:confirm]
  end

  def update_results(input)
    start_mode(:playing) if input[:confirm] && @mode_time > RESTART_DELAY
  end

  def update_playing(dt, input)
    @time_left -= dt
    @penalty_flash -= dt
    fire_turret if input[:fire]
    @scoring.update(dt)
    @spawner.update(dt, @time_left, doom).each do |event|
      react_to(event)
    end
    update_sprays(dt)
    @invaders.update(dt).each do |invader|
      impact(invader)
    end
    @bullets.collide(@invaders.list) do |invader, bullet|
      hit_invader(invader, bullet)
    end
    countdown_beep
    start_finale if @time_left <= 0.0
  end

  def react_to(spawner_event)
    case spawner_event
    when :plate then break_plate
    when :brute then @hud.popup('WARNING: BRUTE', CENTER_X, 132, color: Hud::RED, life: 1.4, rise: 4.0)
    when :swarm
      @hud.popup('SWARM!', CENTER_X, 132, color: Hud::PINK, scale: 2, life: 1.2, rise: 4.0)
      play(:beep, gain: 0.5, pitch: 0.7)
    end
  end

  def countdown_beep
    second = @time_left.ceil
    return if second == @last_beep_second

    @last_beep_second = second
    return unless second.between?(1, 5)

    play(:beep, gain: 0.6, pitch: 1.0 + ((5 - second) * 0.12))
    @camera.shake(0.12)
  end

  # --- Turret -----------------------------------------------------------------------------------------------

  def read_input(inputs)
    steer(inputs)
    {
      fire: @autopilot || fire_held?(inputs),
      confirm: confirm_pressed?(inputs),
      pointer: [inputs.mouse.x / PostProcess::SCALE.to_f, inputs.mouse.y / PostProcess::SCALE.to_f]
    }
  end

  # Moving the mouse hands the turret to the pointer; a direction on keys or stick sends it to that side
  def steer(inputs)
    @pointer_active = true if inputs.mouse.moved
    return if inputs.left_right.zero? && inputs.up_down.zero?

    @pointer_active = false
    @target_angle = Math.atan2(inputs.up_down, inputs.left_right)
  end

  def fire_held?(inputs)
    keys = inputs.keyboard.key_held
    pad = inputs.controller_one.key_held
    inputs.mouse.button_left || keys.space || keys.z || keys.j || pad.a || pad.r1
  end

  def confirm_pressed?(inputs)
    keys = inputs.keyboard.key_down
    pad = inputs.controller_one.key_down
    inputs.mouse.click || keys.space || keys.enter || pad.a || pad.start
  end

  def update_turret(dt, input)
    turret_x, turret_y = @turret.position
    if @autopilot
      autopilot_aim
    elsif @pointer_active
      pointer_x, pointer_y = input[:pointer]
      @target_angle = Math.atan2(pointer_y - CENTER_Y, pointer_x - CENTER_X)
      @desired_aim = Math.atan2(pointer_y - turret_y, pointer_x - turret_x)
    else
      target = nearest_invader_in_cone(turret_x, turret_y)
      @desired_aim = target ? Math.atan2(target[:y] - turret_y, target[:x] - turret_x) : @turret.angle
    end
    @turret.update(dt, @target_angle, @desired_aim)
  end

  def nearest_invader_in_cone(x, y)
    in_cone = @invaders.list.select { |invader|
      angle_between(Math.atan2(invader[:y] - y, invader[:x] - x), @turret.angle) < Turret::MAX_AIM
    }
    in_cone.min_by { |invader| ((invader[:x] - x)**2) + ((invader[:y] - y)**2) }
  end

  def autopilot_aim
    target = @invaders.list.min_by { |invader| invader[:distance] }
    return unless target

    @target_angle = Math.atan2(target[:y] - CENTER_Y, target[:x] - CENTER_X)
    turret_x, turret_y = @turret.position
    @desired_aim = Math.atan2(target[:y] - turret_y, target[:x] - turret_x)
  end

  def angle_between(a, b)
    difference = (a - b) % TAU
    difference > Math::PI ? TAU - difference : difference
  end

  def fire_turret
    shot = @turret.fire
    return unless shot

    x, y, dx, dy = shot
    @bullets.fire(x, y, dx, dy)
    @effects.muzzle_flash(x, y, dx, dy)
    @camera.kick(-dx * 0.9, -dy * 0.9)
    @camera.shake(0.02)
    play(:shoot, gain: 0.3, pitch: 0.94 + (rand * 0.12))
  end

  # --- Combat -----------------------------------------------------------------------------------------------

  def hit_invader(invader, bullet)
    @invaders.hit(invader, 1, 1.4)
    @effects.hit_sparks(bullet[:x], bullet[:y], Math.atan2(-bullet[:vy], -bullet[:vx]))
    @camera.shake(0.04)
    play(:hit, gain: 0.35, pitch: 0.9 + (rand * 0.25))
    kill(invader) if invader[:hp] <= 0
  end

  def kill(invader, chain: false)
    @invaders.remove(invader)
    points = @scoring.kill(invader[:score])
    big = invader[:heavy]
    color = Hud::COMBO_COLORS[@scoring.multiplier - 1]
    @hud.popup("+#{points}", invader[:x], invader[:y] + invader[:radius] + 3, color: color, scale: big ? 2 : 1)
    @effects.explode(invader[:x], invader[:y], invader[:blast])
    @effects.disintegrate(invader, @invaders.splat_cloud(invader))
    @camera.freeze(big ? 9 : 3)
    @camera.aberrate(big ? 4.0 : 1.5)
    @camera.flash!([1.0, 0.95, 0.8], 0.45) if big
    play(kill_sound(chain, big), gain: big ? 0.9 : 0.55, pitch: 1.0 + ([@scoring.combo, 16].min * 0.035))
  end

  def kill_sound(chain, big)
    return :chain if chain

    big ? :big_explode : :explode
  end

  def impact(invader)
    x = invader[:x]
    y = invader[:y]
    nx = (x - CENTER_X) / invader[:distance]
    ny = (y - CENTER_Y) / invader[:distance]
    @time_left = [@time_left - PENALTY, 0.0].max
    @penalty_flash = 0.35
    @hud.popup('-1 SEC', x + (nx * 12), y + (ny * 12), color: Hud::RED, life: 1.2)
    @hud.popup('CHAIN LOST', CENTER_X, 132, color: Hud::GREY, life: 1.0) if @scoring.break_chain >= 3
    @effects.explode(x, y, 1.5)
    @effects.lava_burst(x, y, nx, ny, 26, 70.0)
    @effects.light(x, y, 6.0, [2.6, 1.0, 0.4], 70.0, 0.35)
    @camera.shake(0.5)
    @camera.flash!([1.0, 0.2, 0.3], 0.3)
    @camera.freeze(5)
    @camera.aberrate(3.0)
    play(:impact, gain: 0.85)
  end

  def break_plate
    plate = @planet.detach_facing_plate(16.0 + (rand * 10.0))
    return unless plate

    3.times do
      crack = @planet.random_visible_crack
      @effects.lava_burst(*crack, 10, 50.0) if crack
    end
    @effects.lava_burst(plate[:x], plate[:y], plate[:vx] / 20.0, plate[:vy] / 20.0, 18, 40.0)
    @effects.light(plate[:x], plate[:y], 10.0, [2.5, 1.2, 0.4], 70.0, 0.5)
    @camera.shake(0.4)
    @camera.shockwave(plate[:x], plate[:y], speed: 90.0, strength: 3.0, life: 0.5)
    play(:rumble, gain: 0.8)
  end

  def start_finale
    @mode = :finale
    @mode_time = 0.0
    @time_left = 0.0
    @bullets.clear
    @effects.molten_spray(@planet.shatter(55.0))
    @turret.launch(60.0)
    @effects.explode(CENTER_X, CENTER_Y, 4.5)
    @effects.ring(CENTER_X, CENTER_Y, 2.0, 640.0)
    @effects.light(CENTER_X, CENTER_Y, 30.0, [4.0, 3.0, 2.0], 400.0, 1.2)
    @camera.freeze(14)
    @camera.flash!([1.0, 1.0, 1.0], 1.0)
    @camera.shake(1.0)
    @camera.aberrate(7.0)
    @camera.slow_motion(0.35, 1.8)
    @camera.shockwave(CENTER_X, CENTER_Y, speed: 160.0, strength: 7.0, life: 2.0)
    @camera.shockwave(CENTER_X, CENTER_Y, speed: 95.0, strength: 4.0, life: 1.4)
    play(:final, gain: 1.0)
  end

  def update_finale
    t = @mode_time
    if t < 0.3
      @planet.core_flare(1.0 + (t / 0.3 * 0.4), 2.0)
    elsif t < 0.8
      @planet.core_flare(1.4 * ((1.0 - ((t - 0.3) / 0.5))**2), 2.5)
    elsif !@collapsed
      @collapsed = true
      @planet.core_flare(0.0, 0.0)
      collapse_flash
    end
    ring = t * 160.0
    @invaders.list.dup.each do |invader|
      kill(invader, chain: true) if Math.sqrt(((invader[:x] - CENTER_X)**2) + ((invader[:y] - CENTER_Y)**2)) < ring
    end
    finish_round if t > FINALE_LENGTH
  end

  def collapse_flash
    @camera.flash!([1.0, 0.85, 0.7], 0.7)
    @camera.shake(0.6)
    @camera.aberrate(5.0)
    @effects.explode(CENTER_X, CENTER_Y, 2.5)
    play(:big_explode, gain: 0.9, pitch: 0.6)
  end

  def finish_round
    @scoring.finish_round
    @mode = :results
    @mode_time = 0.0
  end

  # --- Effects ----------------------------------------------------------------------------------------------

  def update_sprays(dt)
    @spray_timer -= dt
    return if @spray_timer.positive?

    @spray_timer = (0.7 - (0.55 * doom)) * (0.5 + rand)
    crack = @planet.random_visible_crack
    @effects.lava_burst(*crack, 4 + (doom * 6).to_i, 30.0 + (doom * 25.0)) if crack
  end

  def update_effects(dt)
    planet_gone = %i[finale results].include?(@mode)
    @effects.update(dt, CENTER_X, CENTER_Y, planet_gone ? -1.0 : Planet::RADIUS)
    @bullets.update(dt)
    @hud.update(dt)
  end

  def play(name, gain: 1.0, pitch: 1.0)
    @sfx.play(@audio, name, gain: gain, pitch: pitch) if @audio
  end

  # --- Rendering --------------------------------------------------------------------------------------------

  def render(outputs)
    update_lights
    @bg_batch.clear
    @sky_glow.clear
    @background.render(@bg_batch, @sky_glow, @time)
    @planet.render(@lighting)
    @invaders.render(@lighting)
    @turret_batch.clear
    @turret.render(@turret_batch, @lighting)
    configure_post
    batches = [@bg_batch, @sky_glow, *@planet.batches, *@invaders.batches, @turret_batch, @bullets.render,
               *@effects.batches]
    @post.render(outputs, batches: batches, camera: @camera, hud: @hud.render(self, @camera),
                          waves: @camera.wave_uniforms, time: @time)
    @sfx.play_loop(@audio, :ambience, @mode == :playing ? 0.2 + (0.5 * doom) : 0.12) if @audio
  end

  def update_lights
    @lighting.clear_points
    @effects.add_lights(@lighting)
    heat = @planet.heat * @planet.pulse * @planet.core_scale
    @lighting.add_point(CENTER_X, CENTER_Y, 0.0, 1.5 * heat, 0.55 * heat, 0.2 * heat, 120.0, except: :planet)
  end

  def configure_post
    beat = @planet.beat
    @post.shadow_tint = doom
    @post.vignette = 0.3 + (0.35 * doom)
    @post.bloom = 0.85 + (0.7 * beat * doom)
    @post.aberration = @camera.aberration + (beat * doom * doom * 1.5)
    @post.flash = @camera.flash
    @post.flash_color = @camera.flash_color
  end
end
