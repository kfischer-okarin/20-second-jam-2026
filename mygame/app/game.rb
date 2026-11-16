# The last 20 seconds of a dying planet, for now only to watch: as doom rises over the 20 seconds, its cracks
# glow brighter and wider, it turns faster and its heart beats faster. Then it starts over.
class Game
  ROUND_TIME = 20.0
  CENTER_X = 160.0
  CENTER_Y = 90.0

  attr_reader :post, :boot_ms

  class << self
    attr_accessor :current
  end

  def initialize(args)
    started = Time.now.to_f
    Textures.create(args)
    @planet = Planet.new(CENTER_X, CENTER_Y)
    @background = Background.new
    @lighting = Lighting.new(sun: [-0.55, 0.62, 0.56], sun_color: [1.05, 0.95, 0.85], ambient: [0.16, 0.14, 0.26],
                             rim: [0.25, 0.32, 0.65])
    @camera = Camera.new
    @post = PostProcess.new
    @post.shadow_tint_color = [0.10, 0.0, 0.015]
    @frame_stats = FrameStats.new
    @bg_batch = SplatBatch.new(:background, parallax: 0.3)
    @sky_glow = SplatBatch.new(:glow, parallax: 0.3)
    @time = 0.0
    @boot_ms = ((Time.now.to_f - started) * 1000).round
  end

  def tick(args)
    @frame_stats.measure do
      @camera.update(1.0 / 60)
      update((1.0 / 60) * @camera.time_scale) unless @camera.frozen?
      render(args.outputs)
    end
  end

  # See FrameStats
  def performance
    @frame_stats.values
  end

  def doom
    (@time % ROUND_TIME) / ROUND_TIME
  end

  private

  def update(dt)
    @time += dt
    @planet.update(dt, doom)
  end

  def render(outputs)
    @bg_batch.clear
    @sky_glow.clear
    @background.render(@bg_batch, @sky_glow, @time)
    @planet.render(@lighting)
    configure_post
    batches = [@bg_batch, @sky_glow, *@planet.batches]
    @post.render(outputs, batches: batches, camera: @camera, hud: [], waves: @camera.wave_uniforms, time: @time)
  end

  def configure_post
    beat = @planet.beat
    @post.shadow_tint = doom
    @post.vignette = 0.3 + (0.35 * doom)
    @post.bloom = 0.85 + (0.7 * beat * doom)
    @post.aberration = @camera.aberration + (beat * doom * doom * 1.5)
  end
end
