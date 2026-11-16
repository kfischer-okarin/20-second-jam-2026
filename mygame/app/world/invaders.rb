# The invaders: SDF-sculpted ships baked into splats, flying in polar coordinates around the planet.
# A new kind of invader is a TYPES entry plus the method that returns its SDF parts.
class Invaders
  # Everything that sets one kind apart. Required:
  #   parts: class method returning the SDF parts (see SdfBaker), bake: SdfBaker.bake options
  #   radius: hit radius in model units, scale: on-screen size of the model, hp:, score:,
  #   speed: pixels per second towards the planet
  # Optional (see DEFAULTS):
  #   pitch: tilt towards the viewer, blast: explosion size on death, heavy: bigger kill feedback,
  #   wobble: sideways sway in pixels, orbit_speed: circling speed (0 dives straight in),
  #   faces_planet: points its front (-y) at the planet instead of spinning,
  #   layer: :solid or :glow (translucent, glowing kinds; see guides/rendering.md),
  #   debris_glow: the Effects::RAMPS ramp its glowing splats turn into when it falls apart
  TYPES = {
    drone: {
      parts: :drone_parts, bake: { bounds: [-6, -6, -6, 6, 6, 6], spacing: 0.8, size: 2.4, seed: 31 },
      radius: 5.0, scale: 1.35, hp: 1, score: 100, speed: 30.0, pitch: 0.35, wobble: 9.0
    },
    saucer: {
      parts: :saucer_parts, bake: { bounds: [-9, -4, -9, 9, 5, 9], spacing: 0.9, size: 2.6, seed: 32 },
      radius: 8.0, scale: 1.3, hp: 3, score: 250, speed: 15.0, pitch: 0.55, blast: 1.4, orbit_speed: 0.35,
      debris_glow: :toxic
    },
    brute: {
      parts: :brute_parts, bake: { bounds: [-12, -9, -8, 12, 10, 9], spacing: 1.0, size: 2.9, seed: 33 },
      radius: 10.0, scale: 1.35, hp: 12, score: 1000, speed: 7.5, pitch: 0.25, blast: 2.4, heavy: true,
      faces_planet: true, debris_glow: :fire
    }
  }.freeze
  DEFAULTS = {
    pitch: 0.4, blast: 1.0, heavy: false, wobble: 0.0, orbit_speed: 0.0, faces_planet: false, layer: :solid,
    debris_glow: :magenta
  }.freeze

  attr_reader :list

  def self.models
    ModelCache.fetch(:invaders) do
      TYPES.to_a.map { |type, info| [type, SdfBaker.bake(send(info[:parts]), **info[:bake])] }.to_h
    end
  end

  def self.drone_parts
    tilt = 0.45
    c = Math.cos(tilt)
    s = Math.sin(tilt)
    [
      { sdf: ->(x, y, z) { Sdf.sphere(x, y, z, 2.7) }, color: [196, 86, 150] },
      { sdf: ->(x, y, z) { Sdf.torus(x, (y * c) - (z * s), (y * s) + (z * c), 4.4, 0.7) }, color: [200, 210, 228] },
      { sdf: ->(x, y, z) { Sdf.sphere(x, y, z - 2.2, 1.3) }, color: [255, 40, 90], emission: 1.0 }
    ]
  end

  # The rim lights repeat around the y axis, so the distance only needs the nearest of the seven
  def self.saucer_parts
    sector = Math::PI * 2 / 7
    [
      { sdf: ->(x, y, z) { Sdf.ellipsoid(x, y, z, 7.6, 1.9, 7.6) }, color: [176, 188, 214] },
      { sdf: ->(x, y, z) { Sdf.torus(x, y + 0.3, z, 6.6, 0.8) }, color: [90, 105, 150], blend: 0.5 },
      { sdf: ->(x, y, z) { Sdf.sphere(x, y - 1.0, z, 3.3) }, color: [99, 199, 77], emission: 0.6 },
      { sdf: lambda { |x, y, z|
        angle = ((Math.atan2(z, x) / sector).round * sector)
        Sdf.sphere(x - (Math.cos(angle) * 6.6), y + 0.3, z - (Math.sin(angle) * 6.6), 0.95)
      }, color: [254, 231, 97], emission: 1.0 }
    ]
  end

  # Mirrored around x = 0, so every part is evaluated on the positive side only
  def self.brute_parts
    [
      { sdf: ->(x, y, z) { Sdf.ellipsoid(x, y, z, 7.4, 5.6, 5.8) }, color: [214, 52, 68] },
      { sdf: ->(x, y, z) { Sdf.capsule(x.abs, y, z, [3.0, 3.0, -0.5], [5.5, 8.0, -1.5], 1.1) }, color: [70, 40, 60],
        blend: 1.2 },
      { sdf: ->(x, y, z) { Sdf.capsule(x.abs, y, z, [5.0, -2.0, 2.0], [9.0, -5.5, 4.0], 1.4) }, color: [120, 62, 66],
        blend: 1.0 },
      { sdf: ->(x, y, z) { Sdf.sphere(x.abs - 9.4, y + 6.0, z - 4.3, 2.0) }, color: [234, 212, 170], blend: 0.6 },
      { sdf: ->(x, y, z) { Sdf.sphere(x.abs - 2.4, y - 1.2, z - 5.0, 1.25) }, color: [254, 231, 97], emission: 1.0 }
    ]
  end

  def initialize(planet)
    @planet = planet
    @models = Invaders.models
    @batches = { solid: SplatBatch.new(:solid), glow: SplatBatch.new(:glow) }
    @list = []
  end

  def batches
    @batches.values
  end

  def clear
    @list.clear
  end

  def spawn(type, theta, distance, speed_scale: 1.0)
    info = DEFAULTS.merge(TYPES.fetch(type))
    settings = info.slice(:hp, :scale, :score, :pitch, :blast, :heavy, :wobble, :faces_planet, :layer, :debris_glow)
    invader = settings.merge(
      type: type, model: @models[type], theta: theta, distance: distance, radius: info[:radius] * info[:scale],
      speed: info[:speed] * speed_scale, age: 0.0, phase: rand * Math::PI * 2, spin: rand * Math::PI * 2,
      spin_speed: random_sign * (1.5 + rand), orbit: random_sign * info[:orbit_speed] * (1.0 + (rand * 0.7)),
      flash: 0.0, punch: 0.0, x: 0.0, y: 0.0, vx: 0.0, vy: 0.0
    )
    place(invader, 0.0)
    @list << invader
    invader
  end

  # Moves everyone and returns the invaders that reached the surface (they are removed)
  def update(dt)
    @list.each do |invader|
      invader[:age] += dt
      invader[:flash] = [invader[:flash] - (dt * 9.0), 0.0].max
      invader[:punch] *= Math.exp(-dt * 12.0)
      invader[:spin] += invader[:spin_speed] * dt
      invader[:distance] -= invader[:speed] * dt
      # circling speeds up the closer it gets
      invader[:theta] += invader[:orbit] * dt * 60.0 / [invader[:distance], 50.0].max
      place(invader, dt)
    end
    landed = @list.select { |invader| invader[:distance] <= @planet.radius + (invader[:radius] * 0.4) }
    @list -= landed
    landed
  end

  def hit(invader, damage, push)
    invader[:hp] -= damage
    invader[:flash] = 1.0
    invader[:punch] = 1.0
    invader[:distance] += push
  end

  def remove(invader)
    @list.delete(invader)
  end

  def render(lighting)
    @batches.each_value(&:clear)
    @list.each do |invader|
      SplatRenderer.render(@batches.fetch(invader[:layer]), invader[:model], matrix(invader), invader[:x],
                           invader[:y], 2.0, invader[:scale] * (1.0 + (0.3 * invader[:punch])), lighting,
                           flash: invader[:flash])
    end
  end

  # World positions and colors of an invader's splats, for turning it into debris
  def splat_cloud(invader, every: 2)
    model = invader[:model]
    m = matrix(invader)
    scale = invader[:scale]
    (0...model.count).select { |i| (i % every).zero? }.map do |i|
      x, y, = Rot3.apply(m, model.px[i], model.py[i], model.pz[i])
      [invader[:x] + (x * scale), invader[:y] + (y * scale), model.cr[i], model.cg[i], model.cb[i], model.em[i]]
    end
  end

  private

  def random_sign
    rand < 0.5 ? -1 : 1
  end

  def place(invader, dt)
    theta = invader[:theta]
    distance = invader[:distance]
    wobble = Math.sin((invader[:age] * 3.4) + invader[:phase]) * invader[:wobble]
    wobble *= ((distance - @planet.radius) / 40.0).clamp(0.0, 1.0)
    cos = Math.cos(theta)
    sin = Math.sin(theta)
    x = @planet.x + (cos * distance) - (sin * wobble)
    y = @planet.y + (sin * distance) + (cos * wobble)
    if dt.positive?
      invader[:vx] = (x - invader[:x]) / dt
      invader[:vy] = (y - invader[:y]) / dt
    end
    invader[:x] = x
    invader[:y] = y
  end

  def matrix(invader)
    if invader[:faces_planet]
      sway = Math.sin(invader[:age] * 2.0) * 0.12
      Rot3.mul(Rot3.rot_z(invader[:theta] - (Math::PI / 2) + sway), Rot3.rot_x(invader[:pitch]))
    else
      bank = (invader[:vx] * 0.02).clamp(-0.5, 0.5)
      Rot3.mul(Rot3.rot_z(-bank), Rot3.mul(Rot3.rot_x(invader[:pitch]), Rot3.rot_y(invader[:spin])))
    end
  end
end
