# Milk that missed the coffee: it stays where it lands.
# - On the table and the saucer it spreads into puddles that grow while more lands on them, so a stream dragged
#   across them leaves a trail.
# - On the cup's rim, or over it when the cup runs over, it runs down the outside of the bowl as drips that end
#   in a puddle on the saucer.
# - Wherever it lands from high up it splashes.
# Puddles are [x, z, area, receiver, seed], receivers :table and :saucer; drips are [angle, y, speed, amount]
# with the angle around the cup (0 faces the eye, positive to the right) and y the height of their head.
class Spills
  MAX_PUDDLES = 160
  # Square centimetres a second of full flow covers
  SPREAD = 9.0
  MILK = [244, 238, 226].freeze
  # Small blobs that give each puddle an uneven outline: [dx, dz, radius] as fractions of its radius
  LOBES = Array.new(5) { |i|
    angle = (i * 2.4) + 0.3
    [Math.cos(angle) * 0.55, Math.sin(angle) * 0.5, 0.55 + (Rng.at(41, i, :size) * 0.3)]
  }.freeze

  attr_reader :table_batch, :saucer_batch, :drip_batch, :splashes, :puddles

  def initialize
    @puddles = []
    @drips = []
    @table_batch = SplatBatch.new(:solid, path: :disc)
    @saucer_batch = SplatBatch.new(:solid, path: :disc)
    @drip_batch = SplatBatch.new(:solid, path: :disc)
    @splashes = Particles.new(:solid, ember: [200.0, 190.0, 175.0])
    @rng = Rng.new(77)
    @splatted = 0.0
  end

  # Seconds of full flow spilled so far
  def spilled
    @puddles.sum { |puddle| puddle[2] } / SPREAD
  end

  # Milk lands on a receiver this frame: flow is 0..1, fall the height it fell from
  def land(x, z, flow, fall, receiver, dt)
    area = SPREAD * flow * dt
    puddle = @puddles.find { |other|
      other[3] == receiver && ((other[0] - x)**2) + ((other[1] - z)**2) < (other[2] / Math::PI) * 0.8
    }
    if puddle
      puddle[2] += area
    else
      @puddles << [x, z, area + 0.15, receiver, @puddles.length]
      merge_smallest if @puddles.length > MAX_PUDDLES
    end
    @splatted += flow * dt * (0.4 + (fall * 0.25))
  end

  # Milk caught by the rim at angle starts running down the outside
  def drip(angle, amount)
    near = @drips.find { |other| (other[0] - angle).abs < 0.12 && other[1] > Cup::RIM_Y - 0.6 }
    if near
      near[3] += amount
    else
      @drips << [angle, Cup::RIM_Y, 0.0, amount]
    end
  end

  # Called once per frame: splash_at is [screen_x, screen_y, scale] where the milk lands, or nil. Drips that
  # reach the bottom of the bowl drop onto the saucer.
  def update(dt, splash_at)
    @drips.each do |drip|
      drip[2] = [drip[2] + (dt * 2.2), 0.8 + (drip[3] * 6.0)].min
      drip[1] -= drip[2] * dt
      next if drip[1] > 2.2

      radius = Cup.outer_radius(2.2) + 0.5
      land(Math.sin(drip[0]) * radius, Math.cos(drip[0]) * radius, drip[3] * 2.0, 0.0, :saucer, 1.0)
    end
    @drips.reject! do |drip|
      drip[1] <= 2.2
    end
    splash(splash_at) if splash_at
    @splashes.update(dt, 0.0, -2000.0, 1800.0)
  end

  # Fills the batches: puddles on the table, puddles on the saucer, drips on the cup. table_point and cup_point
  # turn world positions into [screen_x, screen_y, scale, elevation].
  def render(table_point, cup_point, light)
    shade = light.map { |channel| channel.clamp(0.0, 1.6) }
    @table_batch.clear
    @saucer_batch.clear
    @puddles.each do |x, z, area, receiver, seed|
      if receiver == :table
        render_puddle(@table_batch, table_point.call(x, 0.02, z), area, seed, shade)
      else
        render_puddle(@saucer_batch, cup_point.call(x, Cup::SAUCER_Y + 0.05, z), area, seed, shade)
      end
    end
    render_drips(cup_point, shade)
  end

  private

  def merge_smallest
    smallest = @puddles.min_by { |puddle| puddle[2] }
    @puddles.delete(smallest)
    nearest = @puddles.min_by { |puddle| ((puddle[0] - smallest[0])**2) + ((puddle[1] - smallest[1])**2) }
    nearest[2] += smallest[2]
  end

  def render_puddle(batch, place, area, seed, shade)
    sx, sy, scale, elevation = place
    radius = Math.sqrt(area / Math::PI)
    flat = Math.sin(elevation)
    r = MILK[0] * shade[0]
    g = MILK[1] * shade[1]
    b = MILK[2] * shade[2]
    w = radius * 2.0 * scale
    batch.add(sx, sy, w * 1.15, w * 1.15 * flat, 0.0, r, g, b, 255)
    LOBES.each_with_index do |(dx, dz, size), i|
      turn = Rng.at(seed, i, :turn) * 6.28
      ox = (dx * Math.cos(turn)) - (dz * Math.sin(turn))
      oz = (dx * Math.sin(turn)) + (dz * Math.cos(turn))
      lobe = w * size
      batch.add(sx + (ox * w * 0.5), sy - (oz * w * 0.5 * flat), lobe, lobe * flat, 0.0, r, g, b, 255)
    end
    # The sun's reflection on the far edge of a wet puddle
    glint = [w * 0.35, 1.5].max
    batch.add(sx, sy + (w * 0.32 * flat), glint, glint * 0.5, 0.0, 255, 255, 255, 255) if w > 3.0
  end

  def render_drips(cup_point, shade)
    batch = @drip_batch
    batch.clear
    r = MILK[0] * shade[0] * 0.95
    g = MILK[1] * shade[1] * 0.95
    b = MILK[2] * shade[2] * 0.95
    @drips.each do |angle, head, _speed, amount|
      next if Math.cos(angle) < -0.15

      width = 0.22 + [amount * 1.5, 0.35].min
      y = Cup::RIM_Y
      while y > head
        radius = Cup.outer_radius(y) + 0.05
        sx, sy, scale, = cup_point.call(Math.sin(angle) * radius, y + Cup::BASE_Y, Math.cos(angle) * radius)
        swell = y - head < 0.4 ? 1.5 : 1.0
        batch.add(sx, sy, width * scale * swell, width * scale * swell, 0.0, r, g, b, 255)
        y -= 0.18
      end
    end
  end

  def splash(place)
    return if @splatted < 0.03

    sx, sy, scale = place
    count = (@splatted * 14).clamp(1, 6).to_i
    count.times do
      angle = @rng.range(0.3, Math::PI - 0.3)
      speed = @rng.range(10.0, 30.0) * (0.6 + (scale * 0.04))
      @splashes.spawn(sx, sy, Math.cos(angle) * speed, Math.sin(angle) * speed,
                      life: @rng.range(0.25, 0.5), size: @rng.range(1.5, 2.6), end_size: 1.0, color: MILK,
                      gravity: 160.0)
    end
    @splatted = 0.0
  end
end
