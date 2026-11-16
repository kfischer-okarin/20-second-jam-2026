# Deep space: a nebula band made of large faint splats, twinkling stars and the distant sun that lights the scene
class Background
  SUN_X = 26.0
  SUN_Y = 158.0

  def initialize(seed: 5)
    rng = Rng.new(seed)
    @nebula = Array.new(46) { nebula_splat(rng) }
    @stars = Array.new(150) { star(rng) }
  end

  def render(bg_batch, glow_batch, time)
    @nebula.each do |splat|
      bg_batch.add(*splat)
    end
    @stars.each do |x, y, size, brightness, speed, phase, glows|
      twinkle = 0.65 + (0.35 * Math.sin((time * speed) + phase))
      value = brightness * twinkle
      if glows
        glow_batch.add(x, y, size, size, 0.0, value * 0.75, value * 0.85, value, 255)
      else
        bg_batch.add(x, y, size, size, 0.0, value * 0.8, value * 0.85, value, 255)
      end
    end
    render_sun(glow_batch, time)
  end

  private

  def render_sun(glow_batch, time)
    breathe = 1.0 + (0.04 * Math.sin(time * 1.3))
    glow_batch.add(SUN_X, SUN_Y, 46 * breathe, 46 * breathe, 0.0, 70, 45, 30, 255)
    glow_batch.add(SUN_X, SUN_Y, 18 * breathe, 18 * breathe, 0.0, 200, 160, 110, 255)
    glow_batch.add(SUN_X, SUN_Y, 8, 8, 0.0, 255, 250, 225, 255)
  end

  # A band running diagonally through the screen, darker purple at its edges and bluer near its core
  def nebula_splat(rng)
    t = rng.float
    along = (t * 380.0) - 30.0
    across = rng.range(-1.0, 1.0)
    x = along
    y = 150.0 - (along * 0.42) + (across * 30.0)
    size = rng.range(40.0, 110.0)
    core = 1.0 - across.abs
    r = 60 + (core * 20)
    g = 30 + (core * 40)
    b = 90 + (core * 70)
    [x, y, size, size * rng.range(0.5, 0.9), rng.range(0.0, 180.0), r, g, b, rng.range(14.0, 34.0)]
  end

  def star(rng)
    glows = rng.float < 0.12
    size = glows ? rng.range(2.5, 4.0) : rng.range(1.2, 2.2)
    [rng.range(0.0, 320.0), rng.range(0.0, 180.0), size, rng.range(110.0, 255.0),
     rng.range(1.0, 4.0), rng.range(0.0, 6.3), glows]
  end
end
