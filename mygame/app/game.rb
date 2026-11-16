# A small scene that shows the engine at work, as the starting point for a game: a glowing mushroom, an SDF model
# baked into splats, turns in the last light of the day among fireflies, and wherever the player clicks, a burst
# of spores goes off with a shake, a flash and a shockwave. main.rb needs Game.current, #tick and #post from
# whatever replaces it.
class Game
  CENTER_X = 160.0
  CENTER_Y = 80.0
  MODEL_SCALE = 3.2
  GROUND_Y = 52.0
  # Far below the scene, so debris falls nearly straight down and vanishes when it reaches the ground
  ATTRACTOR_Y = -1000.0
  AUTOPILOT_INTERVAL = 0.6
  TAU = Math::PI * 2
  # The glowing spots on the mushroom's cap, as height and direction angles on its dome
  SPOTS = ([[1.25, 0.0]] + Array.new(6) { |i| [0.75, i * TAU / 6] } +
           Array.new(7) { |i| [0.3, (i + 0.5) * TAU / 7] }).freeze
  RAMPS = {
    spores: [[255, 255, 230], [230, 255, 150], [99, 199, 77], [38, 120, 66], [10, 40, 30], [0, 0, 0]]
  }.freeze

  attr_reader :post, :boot_ms, :bursts
  # Sets off bursts by itself (see GameCli)
  attr_accessor :autopilot

  class << self
    attr_accessor :current
  end

  def self.model
    ModelCache.fetch(:mushroom) do
      SdfBaker.bake(model_parts, bounds: [-9, -9, -9, 9, 7, 9], spacing: 0.8, size: 2.4, seed: 1)
    end
  end

  # A stem that melts into a dome-shaped cap, with glowing spots that stand out of the cap. The spots only ever
  # face away from the viewer where the cap hides them: there is no depth buffer, and they draw over the cap.
  def self.model_parts
    spots = SPOTS.map { |up, around|
      [7.5 * Math.cos(up) * Math.cos(around), 1.5 + (4.2 * Math.sin(up)), 7.5 * Math.cos(up) * Math.sin(around)]
    }
    [
      { sdf: ->(x, y, z) { Sdf.capsule(x, y, z, [0, -7, 0], [0, 1, 0], 1.7) }, color: [234, 212, 170] },
      { sdf: ->(x, y, z) { [Sdf.ellipsoid(x, y - 1.5, z, 7.5, 4.2, 7.5), 1.2 - y].max }, color: [181, 80, 136],
        blend: 0.8 },
      { sdf: ->(x, y, z) { spots.map { |sx, sy, sz| Sdf.sphere(x - sx, y - sy, z - sz, 0.9) }.min },
        color: [44, 232, 245], emission: 1.0, blend: 0.3 }
    ]
  end

  def initialize(args)
    started = Time.now.to_f
    Textures.create(args)
    @lighting = Lighting.new(sun: [0.75, 0.25, 0.6], sun_color: [1.15, 0.75, 0.5], ambient: [0.14, 0.2, 0.22],
                             rim: [0.55, 0.32, 0.2])
    @camera = Camera.new
    @post = PostProcess.new
    @post.background_color = [58, 68, 102]
    @frame_stats = FrameStats.new
    @model = Game.model
    @model_batch = SplatBatch.new(:solid)
    @background = background_batch
    @fireflies = Array.new(24) { |i| firefly(i) }
    @firefly_batch = SplatBatch.new(:glow)
    @spores = Particles.new(:glow, ramps: RAMPS)
    @debris = Particles.new(:solid, ember: [25.0, 60.0, 62.0])
    @lights = []
    @time = 0.0
    @bursts = 0
    @autopilot = false
    @autopilot_timer = 0.0
    @boot_ms = ((Time.now.to_f - started) * 1000).round
  end

  def tick(args)
    @frame_stats.measure do
      dt = 1.0 / 60
      @camera.update(dt)
      update(dt * @camera.time_scale, args.inputs) unless @camera.frozen?
      render(args.outputs)
    end
  end

  # See FrameStats
  def performance
    @frame_stats.values
  end

  private

  def update(dt, inputs)
    @time += dt
    if inputs.mouse.click
      burst(inputs.mouse.x / PostProcess::SCALE.to_f, inputs.mouse.y / PostProcess::SCALE.to_f)
    elsif inputs.keyboard.key_down.space || inputs.controller_one.key_down.a
      burst(CENTER_X, CENTER_Y + 20.0)
    end
    update_autopilot(dt) if @autopilot
    @spores.update(dt, CENTER_X, ATTRACTOR_Y, GROUND_Y - ATTRACTOR_Y)
    @debris.update(dt, CENTER_X, ATTRACTOR_Y, GROUND_Y - ATTRACTOR_Y)
    @lights.each do |light|
      light[2] += dt
    end
    @lights.reject! { |light| light[2] > 0.4 }
  end

  def update_autopilot(dt)
    @autopilot_timer -= dt
    return if @autopilot_timer.positive?

    @autopilot_timer = AUTOPILOT_INTERVAL
    burst(CENTER_X + ((rand - 0.5) * 160.0), CENTER_Y + (rand * 70.0))
  end

  def burst(x, y)
    @bursts += 1
    28.times do
      angle = rand * TAU
      speed = 20.0 + (rand * 70.0)
      @spores.spawn(x, y, Math.cos(angle) * speed, Math.sin(angle) * speed,
                    life: 0.3 + (rand * 0.5), size: 3.0 + (rand * 4.0), end_size: 1.0, ramp: :spores, drag: 2.5,
                    streak: 0.03)
    end
    10.times do
      angle = rand * TAU
      speed = 15.0 + (rand * 35.0)
      @debris.spawn(x, y, Math.cos(angle) * speed, Math.sin(angle) * speed,
                    life: 0.8 + (rand * 0.8), size: 3.5, end_size: 2.0, color: [181, 80, 136], drag: 0.8,
                    gravity: 90.0)
    end
    @lights << [x, y, 0.0]
    @camera.shake(0.35)
    @camera.freeze(3)
    @camera.flash!([0.8, 1.0, 0.7], 0.3)
    @camera.aberrate(2.0)
    @camera.shockwave(x, y, speed: 120.0, strength: 2.5, life: 0.5)
  end

  def render(outputs)
    @lighting.clear_points
    @lights.each do |x, y, age|
      fade = (1.0 - (age / 0.4))**2
      @lighting.add_point(x, y, 10.0, 0.8 * fade, 2.0 * fade, 1.0 * fade, 60.0)
    end
    @model_batch.clear
    SplatRenderer.render(@model_batch, @model, model_matrix, CENTER_X, CENTER_Y, 0.0, MODEL_SCALE, @lighting)
    render_fireflies
    @post.flash = @camera.flash
    @post.flash_color = @camera.flash_color
    @post.aberration = @camera.aberration
    batches = [@background, @model_batch, @debris.render, @firefly_batch, @spores.render]
    @post.render(outputs, batches: batches, camera: @camera, hud: hud, waves: @camera.wave_uniforms, time: @time)
  end

  # Turns around its stem while tilted towards the viewer, who sees the cap from above
  def model_matrix
    Rot3.mul(Rot3.rot_x(0.45), Rot3.rot_y(@time * 0.5))
  end

  def render_fireflies
    batch = @firefly_batch
    batch.clear
    @fireflies.each do |x, y, speed, phase|
      t = (@time * speed) + phase
      glow = 120.0 + (100.0 * Math.sin(t * 2.7))
      batch.add(x + (12.0 * Math.sin(t)), y + (6.0 * Math.sin(t * 1.3)), 2.5, 2.5, 0.0, glow * 0.8, glow, glow * 0.4,
                255)
    end
  end

  def firefly(index)
    [Rng.at(9, index, :x) * 320.0, 40.0 + (Rng.at(9, index, :y) * 110.0), 0.3 + (Rng.at(9, index, :speed) * 0.6),
     Rng.at(9, index, :phase) * TAU]
  end

  # A warm haze along the horizon, hills and the ground, filled once and drawn every frame
  def background_batch
    batch = SplatBatch.new(:background, parallax: 0.3)
    rng = Rng.new(5)
    18.times do
      batch.add(rng.range(-20.0, 340.0), rng.range(55.0, 85.0), rng.range(80.0, 140.0), rng.range(25.0, 40.0), 0.0,
                247, 118, 34, rng.range(14.0, 26.0))
    end
    14.times do
      batch.add(rng.range(-20.0, 340.0), rng.range(44.0, 56.0), rng.range(60.0, 110.0), rng.range(20.0, 34.0), 0.0,
                38, 92, 66, 255)
    end
    10.times do |i|
      batch.add((i * 36.0) - 4.0, 18.0, 70.0, 60.0, 0.0, 25, 60, 62, 255)
    end
    batch
  end

  def hud
    primitives = []
    text(primitives, 'SPLAT ENGINE', 160, 160, scale: 2, color: [254, 231, 97])
    text(primitives, 'CLICK OR PRESS A', 160, 14, color: [192, 203, 220])
    primitives
  end

  def text(primitives, string, x, y, scale: 1, color: [255, 255, 255])
    PixelFont.draw(primitives, string, x, y, scale: scale, color: color, align: :center, outline: [24, 20, 37])
  end
end
