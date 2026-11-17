# The world beyond the table: sky, sun, a meadow with a pond and a few trees on the horizon, and the wall of light
# that the exploding sun throws towards the terrace. It is a backdrop that hangs above the table's far edge
# (View#horizon_y), drawn in screen space.
#
# The wave's progress runs from 0 (a thin line on the horizon) to 1 (it reached the table's edge); the meadow
# behind it is swallowed by light. The pond, a mirror of the brightening sky, lights up first.
class World
  MEADOW_DEPTH = 15.0
  SKY = [[255, 236, 190], [248, 214, 164], [230, 200, 176], [200, 198, 206], [166, 178, 200], [139, 155, 180]].freeze
  SKY_HEIGHT = 240.0
  WHITE = [255, 252, 240].freeze
  # x, height and width of the trees on the horizon, in scene pixels
  TREES = [[42.0, 30.0, 1.0], [226.0, 26.0, 0.9], [244.0, 31.0, 1.05], [262.0, 24.0, 0.85]].freeze
  BLADES = 340
  POND = [82.0, 7.0, 64.0, 5.0].freeze

  attr_reader :sky, :back, :meadow, :glow
  attr_accessor :supernova, :wave, :wind

  def initialize
    @sky = SplatBatch.new(:background, path: :pixel, parallax: 0.4)
    @back = SplatBatch.new(:background, parallax: 0.4)
    @meadow = SplatBatch.new(:background, parallax: 0.7)
    @glow = SplatBatch.new(:glow, parallax: 0.5)
    @supernova = 0.0
    @wave = 0.0
    @wind = 0.0
    @blades = Array.new(BLADES) { |i| blade(i) }
    @canopies = TREES.each_with_index.map { |tree, i| canopy(tree, i) }
  end

  # Sky color at height t (0 on the horizon, 1 high up), brightened by the supernova
  def self.sky_color(t, brightness)
    position = t.clamp(0.0, 1.0) * (SKY.length - 1)
    index = [position.floor, SKY.length - 2].min
    f = position - index
    a = SKY[index]
    b = SKY[index + 1]
    Array.new(3) { |c| a[c] + ((b[c] - a[c]) * f) + ((WHITE[c] - a[c] - ((b[c] - a[c]) * f)) * brightness) }
  end

  # Drawn without the view's tilt, which Terrace adds by shifting the batches
  def render(view, time)
    @edge = view.horizon_y
    @horizon = @edge + MEADOW_DEPTH
    @tilt = view.tilt
    @time = time
    @sky.clear
    @back.clear
    @meadow.clear
    @glow.clear
    render_sky
    render_sun
    render_meadow
    render_pond
    render_trees
    render_wave
  end

  # How far the wave has come across the meadow on screen, 0..1
  def front
    t = @wave.clamp(0.0, 1.0)
    t * t * (1.6 - (0.6 * t))
  end

  private

  def brightness
    (@supernova * 0.08) + (@wave.clamp(0.0, 1.2) * 0.5)
  end

  # A gradient of one pixel high rows: the dithering blends them
  def render_sky
    glow = brightness
    y = @horizon - 6.0
    top = [@horizon + SKY_HEIGHT, 200.0 - @tilt].min
    while y < top
      if y + @tilt > -10.0
        r, g, b = World.sky_color((y - @horizon) / SKY_HEIGHT, glow)
        @sky.add(160.0, y, 360.0, 1.2, 0.0, r, g, b, 255)
      end
      y += 1.0
    end
  end

  def sun_position
    [160.0, @horizon + 36.0]
  end

  def render_sun
    x, y = sun_position
    burst = @supernova
    halo = 70.0 + (burst * 160.0) + (@wave * 60.0)
    @back.add(x, y, halo * 1.4, halo, 0.0, 255, 246, 214, 110 + (burst * 100.0))
    @back.add(x, y, halo * 0.55, halo * 0.5, 0.0, 255, 250, 228, 190)
    core = 13.0 + (burst * 10.0) + (@wave * 12.0)
    @back.add(x, y, core, core, 0.0, 255, 255, 250, 255)
    @glow.add(x, y, core * 1.6, core * 1.6, 0.0, 160 + (burst * 95), 150 + (burst * 90), 120 + (burst * 100), 255)
    render_rays(x, y) if burst.positive?
  end

  # Slowly turning rays around the exploded sun
  def render_rays(x, y)
    strength = @supernova.clamp(0.0, 1.0)
    14.times do |i|
      angle = (i * 360.0 / 14) + (@time * 4.0) + (Math.sin((i * 1.7) + @time) * 3.0)
      length = (80.0 + (Rng.at(5, i, :ray) * 90.0)) * (0.6 + (strength * 0.6))
      c = 60.0 * strength * (0.6 + (0.4 * Math.sin((@time * 1.3) + i)))
      @glow.add(x, y, length, 2.0, angle, c, c * 0.95, c * 0.75, 255)
    end
  end

  def render_meadow
    light = brightness
    rows = 8
    rows.times do |row|
      t = row.fdiv(rows - 1)
      y = @edge - 4.0 + (t * (MEADOW_DEPTH + 2.0))
      # Lush near the table, a golden haze towards the horizon
      r = 62 + (t * 140.0)
      g = 128 + (t * 66.0)
      b = 66 + (t * 50.0)
      r += (255 - r) * light * 0.3
      g += (255 - g) * light * 0.3
      b += (240 - b) * light * 0.3
      8.times do |i|
        @meadow.add(-20.0 + (i * 50.0) + ((row % 2) * 25.0), y, 64.0, 6.0 + (t * 2.0), 0.0, r, g, b, 255)
      end
    end
    render_blades
  end

  # Blades of grass, larger near the table, swaying, lit from behind at their tips
  def render_blades
    sway = 0.18 + (@wind * 0.7)
    flatten = 1.0 - (@wind * 0.45)
    @blades.each do |x, depth, height, lit, phase|
      y = @edge + (depth * MEADOW_DEPTH)
      near = 1.0 - depth
      h = height * (0.35 + (near * 1.1)) * flatten
      angle = 90.0 + (Math.sin((@time * (1.1 + (@wind * 2.5))) + phase + (x * 0.04)) * sway * 40.0) + (@wind * 18.0)
      if lit
        @meadow.add(x, y + (h * 0.5), 1.2, h, angle, 236, 222, 120, 255)
      else
        shade = 0.8 + (depth * 0.6)
        @meadow.add(x, y + (h * 0.5), 1.4, h, angle, 46 * shade, 110 * shade, 60 * shade, 255)
      end
    end
  end

  def blade(index)
    depth = Rng.at(21, index, :depth)**0.7
    [(Rng.at(21, index, :x) * 330.0) - 5.0, depth, 2.5 + (Rng.at(21, index, :height) * 4.0),
     Rng.at(21, index, :lit) < 0.3, Rng.at(21, index, :phase) * 6.28]
  end

  def render_pond
    x, depth, w, h = POND
    y = @edge + depth
    lit = ((front - 0.12) * 2.5).clamp(0.0, 1.0)
    r, g, b = World.sky_color(0.55, brightness)
    @meadow.add(x, y, w + 6.0, h + 2.5, 0.0, 30, 70, 58, 255)
    @meadow.add(x, y, w, h, 0.0, r, g, b, 255)
    @meadow.add(x, y + 0.8, w * 0.8, h * 0.4, 0.0, 255, 250, 235, 200)
    6.times do |i|
      shimmer = Math.sin((@time * 3.0) + (i * 2.1))
      next if shimmer < 0.3

      gx = x - (w * 0.35) + (i * w * 0.14) + (Math.sin((@time * 0.7) + i) * 3.0)
      c = 90.0 * shimmer
      @glow.add(gx, y + Math.sin(i * 1.3), 4.0, 1.0, 0.0, c, c, c * 0.9, 255)
    end
    @glow.add(x, y, w * 1.2, h * 3.0, 0.0, 255 * lit, 240 * lit, 200 * lit, 255) if lit.positive?
  end

  # Soft blobs of foliage around the top of the trunk: [dx, dy, size]
  def canopy(tree, index)
    _x, height, width = tree
    Array.new(14) do |i|
      angle = Rng.at(index, i, :angle) * 6.28
      reach = Math.sqrt(Rng.at(index, i, :reach)) * height * 0.3
      [Math.cos(angle) * reach * width, (height * 0.64) + (Math.sin(angle) * reach * 0.8),
       height * (0.26 + (Rng.at(index, i, :s) * 0.16))]
    end
  end

  # Backlit silhouettes with a rim of light on the side towards the sun, swaying in the wind
  def render_trees
    swallowed = ((front - 0.3) * 5.0).clamp(0.0, 1.0)
    return if swallowed >= 1.0

    TREES.each_with_index do |(x, height, _width), index|
      base = @horizon - 2.0
      @back.add(x, base + (height * 0.25), 2.2, height * 0.5, 0.0, *blend([62, 39, 49], WHITE, swallowed), 255)
      render_canopy(index, x, base, height, swallowed)
    end
  end

  # All the foliage first, then the rims of light on top of it
  def render_canopy(index, x, base, height, swallowed)
    toward_sun = x < 160 ? 1.0 : -1.0
    dark = blend([38, 80, 62], WHITE, swallowed)
    rim = blend([170, 196, 110], WHITE, swallowed)
    blobs = @canopies[index].each_with_index.map { |(dx, dy, s), i|
      [x + dx + (Math.sin((@time * (0.8 + @wind)) + i + index) * (0.25 + (@wind * 1.4)) * (dy / height)), dy, s, dx]
    }
    blobs.each do |bx, dy, s, _dx|
      @back.add(bx, base + dy, s, s * 0.85, 0.0, *dark, 255)
    end
    # rubocop:disable-next Style/CombinableLoops
    blobs.each do |bx, dy, s, dx|
      next unless (dx * toward_sun) > -1.0 && dy > height * 0.55

      @back.add(bx + (toward_sun * s * 0.22), base + dy + (s * 0.18), s * 0.4, s * 0.3, 0.0, *rim, 160)
    end
  end

  def blend(color, other, t)
    [color[0] + ((other[0] - color[0]) * t), color[1] + ((other[1] - color[1]) * t),
     color[2] + ((other[2] - color[2]) * t)]
  end

  # The wall of light: everything behind its front is white, the front itself a glowing line
  def render_wave
    return unless @wave.positive?

    y = @horizon - ((@horizon - @edge + 3.0) * front)
    height = @horizon - y + 3.0
    8.times do |i|
      @meadow.add(-20.0 + (i * 50.0), y + (height * 0.5), 70.0, height + 2.0, 0.0, 255, 250, 232, 255)
    end
    flicker = 0.85 + (0.15 * Math.sin(@time * 9.0))
    8.times do |i|
      @glow.add(-20.0 + (i * 50.0), y, 72.0, 3.0, 0.0, 255 * flicker, 245 * flicker, 210 * flicker, 255)
      @glow.add(-20.0 + (i * 50.0), y + 3.0, 72.0, 10.0, 0.0, 70, 64, 50, 255)
    end
  end
end
