# Wisps of steam rising from the coffee: soft additive splats that sway as they rise and fade. The wind of the
# approaching light blows them back towards the eye, which on screen pushes them down and apart.
class Steam
  COUNT = 26
  LIFE = 3.2

  attr_reader :batch
  attr_accessor :wind, :strength

  def initialize
    @batch = SplatBatch.new(:glow)
    @rng = Rng.new(9)
    # [x, y, drift, scale, age, phase]; they start one after another
    @wisps = Array.new(COUNT) { |i| [0.0, 0.0, 0.0, 0.0, -LIFE * i / COUNT, @rng.range(0.0, 6.28)] }
    @wind = 0.0
    @strength = 1.0
  end

  # source returns a random [screen_x, screen_y, scale] on the coffee's surface
  def update(dt, &source)
    @wisps.each do |wisp|
      wisp[4] += dt
      if wisp[4] >= LIFE || (wisp[4] >= 0.0 && wisp[3].zero?)
        x, y, scale = source.call(@rng)
        wisp[0] = x
        wisp[1] = y
        wisp[2] = @rng.range(-1.0, 1.0)
        wisp[3] = scale
        wisp[4] = 0.0
      end
      age = wisp[4]
      next if age.negative?

      rise = (5.0 + (age * 3.0)) * (1.0 - (@wind * 0.8))
      sway = Math.sin((age * 1.6) + wisp[5]) * (2.0 + (age * 1.5))
      wisp[0] += ((wisp[2] * 1.5) + sway + (@wind * wisp[2] * 14.0)) * dt
      wisp[1] += (rise - (@wind * 16.0)) * dt
    end
  end

  def render
    batch = @batch
    batch.clear
    @wisps.each do |x, y, _drift, scale, age, phase|
      next if age.negative? || scale.zero?

      t = age / LIFE
      fade = Math.sin(t * Math::PI) * @strength
      next if fade <= 0.02

      size = (2.0 + (age * 4.0)) * (scale / 11.0)
      c = 26.0 * fade
      stretch = 1.6 + (@wind * 1.5)
      angle = 90.0 + (Math.sin((age * 2.0) + phase) * 25.0)
      batch.add(x, y, size * stretch, size, angle, c, c * 0.97, c * 0.92, 255)
    end
    batch
  end
end
