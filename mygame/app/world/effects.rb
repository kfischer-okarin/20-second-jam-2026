# Particles, expanding rings and short-lived point lights for shots, hits, explosions and lava, plus the camera
# shake and shockwaves that go with explosions
class Effects
  TAU = Math::PI * 2
  RAMPS = {
    fire: [[255, 255, 235], [255, 236, 140], [254, 174, 52], [247, 118, 34], [190, 50, 34], [80, 16, 30], [0, 0, 0]],
    spark: [[255, 255, 255], [255, 240, 170], [254, 190, 80], [247, 118, 34], [120, 30, 20], [0, 0, 0]],
    plasma: [[255, 255, 255], [190, 250, 255], [44, 232, 245], [0, 130, 210], [10, 30, 90], [0, 0, 0]],
    lava: [[255, 245, 180], [254, 200, 80], [247, 118, 34], [200, 40, 30], [90, 14, 24], [0, 0, 0]],
    magenta: [[255, 255, 255], [255, 170, 220], [246, 80, 160], [181, 40, 120], [60, 10, 50], [0, 0, 0]],
    toxic: [[255, 255, 230], [200, 255, 150], [99, 199, 77], [38, 120, 66], [10, 40, 30], [0, 0, 0]]
  }.freeze
  # What solid debris cools down to
  EMBER = [62.0, 30.0, 44.0].freeze

  def initialize(camera)
    @camera = camera
    @fx = Particles.new(:glow, ramps: RAMPS)
    @debris = Particles.new(:solid, ember: EMBER)
    @ring_batch = SplatBatch.new(:glow, path: :ring)
    clear
  end

  def clear
    @fx.clear
    @debris.clear
    @rings = []
    @flashes = []
  end

  def explode(x, y, scale)
    (12 * scale).to_i.times do
      angle = rand * TAU
      speed = (8.0 + (rand * 34.0)) * Math.sqrt(scale)
      @fx.spawn(x, y, Math.cos(angle) * speed, Math.sin(angle) * speed,
                life: 0.25 + (rand * 0.4), size: (5.0 + (rand * 5.0)) * Math.sqrt(scale), end_size: 1.0,
                ramp: :fire, drag: 2.5)
    end
    (10 * scale).to_i.times do
      angle = rand * TAU
      speed = 60.0 + (rand * 110.0 * Math.sqrt(scale))
      @fx.spawn(x, y, Math.cos(angle) * speed, Math.sin(angle) * speed,
                life: 0.2 + (rand * 0.3), size: 1.5, end_size: 0.6, ramp: :spark, drag: 3.0, streak: 0.045)
    end
    (3 * scale).to_i.times do
      angle = rand * TAU
      speed = 6.0 + (rand * 16.0)
      @debris.spawn(x, y, Math.cos(angle) * speed, Math.sin(angle) * speed,
                    life: 0.35 + (rand * 0.4), size: 3.5 + (rand * 3.0), end_size: 6.0, color: [118, 104, 150],
                    drag: 1.6)
    end
    ring(x, y, 0.3 * Math.sqrt(scale), 26.0 * scale)
    @camera.shockwave(x, y, speed: 110.0 * Math.sqrt(scale), strength: 1.8 * scale, life: 0.4)
    light(x, y, 8.0, [2.4, 1.4, 0.6], 40.0 * scale, 0.2)
    @camera.shake(0.18 * scale)
  end

  # The invader falls apart into the very splats it was made of (see Invaders#splat_cloud): glowing splats, or
  # all of them for kinds in the glow layer, become light in its debris_glow ramp, the rest solid chunks
  def disintegrate(invader, splat_cloud)
    splat_cloud.each do |x, y, r, g, b, emission|
      dx = x - invader[:x]
      dy = y - invader[:y]
      distance = Math.sqrt((dx * dx) + (dy * dy)) + 0.01
      speed = 20.0 + (rand * 60.0)
      vx = (dx / distance * speed) + (invader[:vx] * 0.3) + ((rand - 0.5) * 16.0)
      vy = (dy / distance * speed) + (invader[:vy] * 0.3) + ((rand - 0.5) * 16.0)
      if emission > 0.5 || invader[:layer] == :glow
        @fx.spawn(x, y, vx, vy, life: 0.3 + (rand * 0.4), size: 2.2, end_size: 0.8, ramp: invader[:debris_glow],
                                drag: 2.0)
      else
        @debris.spawn(x, y, vx, vy, life: 0.5 + (rand * 0.7), size: 2.8, end_size: 1.6,
                                    color: [r * 1.15, g * 1.15, b * 1.15], drag: 1.4, gravity: 25.0)
      end
    end
  end

  # Molten drops thrown out along the normal (nx, ny) that fall back onto the planet
  def lava_burst(x, y, nx, ny, count, speed)
    count.times do
      spread = (rand - 0.5) * 1.6
      cos = Math.cos(spread)
      sin = Math.sin(spread)
      velocity = speed * (0.35 + (rand * 0.65))
      @fx.spawn(x, y, ((nx * cos) - (ny * sin)) * velocity, ((nx * sin) + (ny * cos)) * velocity,
                life: 0.6 + (rand * 0.7), size: 2.5 + (rand * 2.0), end_size: 1.0, ramp: :lava, drag: 0.4,
                gravity: 70.0)
    end
  end

  # points are [x, y, normal_x, normal_y] (see Planet#shatter)
  def molten_spray(points)
    points.each do |x, y, nx, ny|
      speed = 40.0 + (rand * 110.0)
      @fx.spawn(x, y, (nx + ((rand - 0.5) * 0.6)) * speed, (ny + ((rand - 0.5) * 0.6)) * speed,
                life: 0.8 + (rand * 1.2), size: 3.0 + (rand * 3.0), end_size: 1.0, ramp: :lava, drag: 0.6)
    end
  end

  def muzzle_flash(x, y, dx, dy)
    @fx.spawn(x, y, dx * 30.0, dy * 30.0, life: 0.08, size: 8.0, end_size: 3.0, ramp: :plasma)
    2.times do
      spread = (rand - 0.5) * 0.9
      speed = 60.0 + (rand * 50.0)
      @fx.spawn(x, y, ((dx * Math.cos(spread)) - (dy * Math.sin(spread))) * speed,
                ((dx * Math.sin(spread)) + (dy * Math.cos(spread))) * speed,
                life: 0.12, size: 1.5, end_size: 0.8, ramp: :plasma, drag: 6.0, streak: 0.05)
    end
    light(x, y, 8.0, [0.8, 1.6, 2.2], 30.0, 0.07)
  end

  # Sparks bouncing back towards the shooter (back is the angle they fly off in)
  def hit_sparks(x, y, back)
    5.times do
      angle = back + ((rand - 0.5) * 1.6)
      speed = 40.0 + (rand * 70.0)
      @fx.spawn(x, y, Math.cos(angle) * speed, Math.sin(angle) * speed,
                life: 0.15 + (rand * 0.15), size: 1.4, end_size: 0.6, ramp: :plasma, drag: 5.0, streak: 0.06)
    end
  end

  def ring(x, y, life, size)
    @rings << { x: x, y: y, age: 0.0, life: life, size: size }
  end

  def light(x, y, z, color, radius, life)
    @flashes << { x: x, y: y, z: z, color: color, radius: radius, life: life, age: 0.0 }
  end

  # A negative planet radius means the planet is gone (see Particles#update)
  def update(dt, planet_x, planet_y, planet_radius)
    @fx.update(dt, planet_x, planet_y, planet_radius)
    @debris.update(dt, planet_x, planet_y, planet_radius)
    [@rings, @flashes].each do |effects|
      effects.each do |effect|
        effect[:age] += dt
      end
      effects.reject! { |effect| effect[:age] >= effect[:life] }
    end
  end

  def add_lights(lighting)
    @flashes.each do |flash|
      fade = 1.0 - (flash[:age] / flash[:life])
      fade *= fade
      color = flash[:color]
      lighting.add_point(flash[:x], flash[:y], flash[:z], color[0] * fade, color[1] * fade, color[2] * fade,
                         flash[:radius])
    end
  end

  def batches
    [@debris.render, @fx.render, render_rings]
  end

  private

  def render_rings
    batch = @ring_batch
    batch.clear
    @rings.each do |ring|
      t = ring[:age] / ring[:life]
      size = ring[:size] * (1.0 - ((1.0 - t)**3))
      fade = (1.0 - t)**2
      batch.add(ring[:x], ring[:y], size, size, 0.0, 255 * fade, 220 * fade, 170 * fade, 255)
    end
    batch
  end
end
