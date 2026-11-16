# Short-lived splats in the screen plane, stored as parallel arrays, drawn into one layer (see SplatBatch).
# Particles in the :glow layer take their color from a ramp that ends in black, so they fade out by themselves.
# Particles in the :solid layer keep a base color that cools towards the ember color while their alpha drops
# until the post shader's alpha test eats them, which makes them shrink in hard pixel steps.
class Particles
  RAMP_STEPS = 16

  attr_reader :batch, :count

  def self.ramp_table(stops)
    Array.new(RAMP_STEPS) do |step|
      position = step.fdiv(RAMP_STEPS - 1) * (stops.length - 1)
      index = [position.floor, stops.length - 2].min
      t = position - index
      a = stops[index]
      b = stops[index + 1]
      [a[0] + ((b[0] - a[0]) * t), a[1] + ((b[1] - a[1]) * t), a[2] + ((b[2] - a[2]) * t)]
    end
  end

  # ramps are the color stops for spawn's ramp: by name, from the brightest color to black
  # ({ fire: [[255, 255, 235], [254, 174, 52], [190, 50, 34], [0, 0, 0]] })
  def initialize(layer, ramps: {}, ember: [0.0, 0.0, 0.0])
    @ramps = ramps.map { |name, stops| [name, Particles.ramp_table(stops)] }.to_h
    @ember = ember
    @batch = SplatBatch.new(layer)
    @x = []
    @y = []
    @vx = []
    @vy = []
    @age = []
    @life = []
    @size = []
    @end_size = []
    @ramp = []
    @color = []
    @drag = []
    @gravity = []
    @streak = []
    @count = 0
  end

  def clear
    @count = 0
  end

  # end_size defaults to size (a default value cannot refer to another keyword argument in mruby)
  def spawn(x, y, vx, vy, life:, size:, end_size: nil, ramp: nil, color: nil, drag: 0.0, gravity: 0.0,
            streak: 0.0)
    i = @count
    @x[i] = x
    @y[i] = y
    @vx[i] = vx
    @vy[i] = vy
    @age[i] = 0.0
    @life[i] = life
    @size[i] = size
    @end_size[i] = end_size || size
    @ramp[i] = ramp && @ramps[ramp]
    @color[i] = color
    @drag[i] = drag
    @gravity[i] = gravity
    @streak[i] = streak
    @count += 1
  end

  # Particles with gravity fall towards the attractor and vanish once they come within its radius, like drops
  # falling back onto a planet. A negative radius turns gravity off.
  # Hot loop: kept in one method because a method call per particle costs noticeably in mruby.
  # rubocop:disable-next Metrics/CyclomaticComplexity
  def update(dt, attractor_x, attractor_y, attractor_radius)
    i = 0
    while i < @count
      age = @age[i] + dt
      if age >= @life[i]
        remove(i)
        next
      end

      @age[i] = age
      drag = 1.0 - (@drag[i] * dt)
      drag = 0.0 if drag < 0.0
      vx = @vx[i] * drag
      vy = @vy[i] * drag
      gravity = @gravity[i]
      falls = gravity != 0.0 && attractor_radius > 0.0
      if falls
        dx = attractor_x - @x[i]
        dy = attractor_y - @y[i]
        distance = Math.sqrt((dx * dx) + (dy * dy))
        vx += dx / distance * gravity * dt
        vy += dy / distance * gravity * dt
      end
      x = @x[i] + (vx * dt)
      y = @y[i] + (vy * dt)
      if falls && (((x - attractor_x)**2) + ((y - attractor_y)**2)) < attractor_radius * attractor_radius
        remove(i)
        next
      end

      @vx[i] = vx
      @vy[i] = vy
      @x[i] = x
      @y[i] = y
      i += 1
    end
  end

  def render
    batch = @batch
    batch.clear
    out = batch.data
    j = 0
    rad_to_deg = SplatRenderer::RAD_TO_DEG
    ember = @ember
    i = 0
    while i < @count
      t = @age[i] / @life[i]
      size = @size[i] + ((@end_size[i] - @size[i]) * t)
      ramp = @ramp[i]
      if ramp
        # t stays below 1, so this reaches the final black entry during the last sixteenth of the life
        rgb = ramp[(t * RAMP_STEPS).to_i]
        r = rgb[0]
        g = rgb[1]
        b = rgb[2]
        a = 255
      else
        base = @color[i]
        keep = 1.0 - t
        r = (base[0] * keep) + (ember[0] * t)
        g = (base[1] * keep) + (ember[1] * t)
        b = (base[2] * keep) + (ember[2] * t)
        a = 255 * (1.0 - (t * t))
      end
      streak = @streak[i]
      vx = @vx[i]
      vy = @vy[i]
      if streak > 0.0
        speed = Math.sqrt((vx * vx) + (vy * vy))
        width = size + (speed * streak)
        angle = Math.atan2(vy, vx) * rad_to_deg
      else
        width = size
        angle = 0.0
      end
      out[j] = @x[i]
      out[j + 1] = @y[i]
      out[j + 2] = width
      out[j + 3] = size
      out[j + 4] = angle
      out[j + 5] = r
      out[j + 6] = g
      out[j + 7] = b
      out[j + 8] = a
      j += 9
      i += 1
    end
    batch.count = j.idiv(9)
    batch
  end

  private

  def remove(index)
    last = @count - 1
    if index != last
      @x[index] = @x[last]
      @y[index] = @y[last]
      @vx[index] = @vx[last]
      @vy[index] = @vy[last]
      @age[index] = @age[last]
      @life[index] = @life[last]
      @size[index] = @size[last]
      @end_size[index] = @end_size[last]
      @ramp[index] = @ramp[last]
      @color[index] = @color[last]
      @drag[index] = @drag[last]
      @gravity[index] = @gravity[last]
      @streak[index] = @streak[last]
    end
    @count = last
  end
end
