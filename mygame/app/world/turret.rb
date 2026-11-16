# The player's twin-barrelled turret. It glides along the planet's rim and aims within a cone around the outward
# direction. All of its parts are SDFs baked into splats.
class Turret
  # The models are sculpted in units that read too small at the scene's resolution
  SIZE = 1.6
  TILT = 0.5
  PIVOT = 3.4
  BARREL_X = 1.35
  BARREL_LENGTH = 8.0
  MAX_TURN_SPEED = 6.0
  MAX_AIM = 1.3
  FIRE_INTERVAL = 0.085
  RECOIL = 2.4

  attr_reader :angle, :aim, :heat

  def self.models
    ModelCache.fetch(:turret) do
      {
        base: SdfBaker.bake(base_parts, bounds: [-8, -2, -8, 8, 5, 8], spacing: 0.9, size: 2.8, seed: 21,
                                        keep: ->(_x, y, _z) { y > -1.2 }),
        head: SdfBaker.bake(head_parts, bounds: [-5, -3, -5, 5, 4, 5], spacing: 0.85, size: 2.6, seed: 22),
        barrel: SdfBaker.bake(barrel_parts, bounds: [-2, -1, -2, 2, BARREL_LENGTH + 1.5, 2], spacing: 0.7,
                                            size: 2.0, seed: 23)
      }
    end
  end

  def self.base_parts
    [
      { sdf: ->(x, y, z) { Sdf.ellipsoid(x, y + 0.6, z, 6.2, 3.8, 6.2) }, color: [82, 92, 124] },
      { sdf: ->(x, y, z) { Sdf.torus(x, y - 0.4, z, 5.6, 0.85) }, color: [44, 232, 245], emission: 0.9, blend: 0.3 }
    ]
  end

  def self.head_parts
    [
      { sdf: ->(x, y, z) { Sdf.round_box(x, y, z, 3.3, 2.1, 2.9, 1.1) }, color: [150, 164, 190] },
      { sdf: ->(x, y, z) { Sdf.round_box(x, y - 1.9, z, 2.2, 0.5, 2.0, 0.4) }, color: [90, 105, 136], blend: 0.5 },
      { sdf: ->(x, y, z) { Sdf.sphere(x, y - 0.2, z - 2.7, 0.95) }, color: [44, 232, 245], emission: 1.0 }
    ]
  end

  def self.barrel_parts
    [
      { sdf: ->(x, y, z) { Sdf.capsule(x, y, z, [0, 0, 0], [0, BARREL_LENGTH - 1.2, 0], 0.85) }, color: [70, 80, 110] },
      { sdf: ->(x, y, z) { Sdf.torus(x, y - (BARREL_LENGTH - 0.6), z, 0.9, 0.55) }, color: [255, 150, 70],
        emission: 1.0, blend: 0.3 }
    ]
  end

  def initialize(planet)
    @planet = planet
    @models = Turret.models
    reset
  end

  def reset
    @angle = Math::PI / 2
    @velocity = 0.0
    @aim = @angle
    @recoil = [0.0, 0.0]
    @punch = 0.0
    @heat = 0.0
    @cooldown = 0.0
    @next_barrel = 0
    @flight = nil
  end

  def flying?
    !@flight.nil?
  end

  # Turns towards the target rim angle and points the barrels towards the desired aim angle
  def update(dt, target_angle, desired_aim)
    if @flight
      update_flight(dt)
      return
    end

    difference = wrap(target_angle - @angle)
    desired_velocity = (difference * 10.0).clamp(-MAX_TURN_SPEED, MAX_TURN_SPEED)
    @velocity += (desired_velocity - @velocity) * [dt * 14.0, 1.0].min
    @angle = wrap(@angle + (@velocity * dt))
    relative = wrap(desired_aim - @angle).clamp(-MAX_AIM, MAX_AIM)
    @aim = wrap(@aim + (wrap(@angle + relative - @aim) * [dt * 22.0, 1.0].min))
    decay = Math.exp(-dt * 13.0)
    @recoil = @recoil.map { |recoil| recoil * decay }
    @punch *= Math.exp(-dt * 16.0)
    @heat = [@heat - (dt * 0.9), 0.0].max
    @cooldown -= dt
  end

  # Fires one barrel if it is ready; returns [muzzle_x, muzzle_y, direction_x, direction_y] or nil
  def fire
    return nil if @flight || @cooldown > 0.0

    @cooldown = FIRE_INTERVAL
    barrel = @next_barrel
    @next_barrel = 1 - barrel
    @recoil[barrel] = RECOIL
    @punch = 1.0
    @heat = [@heat + 0.07, 1.0].min
    pivot_x, pivot_y = pivot
    m = head_matrix
    side = barrel.zero? ? -BARREL_X : BARREL_X
    muzzle_x, muzzle_y, = Rot3.apply(m, side * SIZE, (BARREL_LENGTH + 0.5) * SIZE, 0.0)
    [pivot_x + muzzle_x, pivot_y + muzzle_y, Math.cos(@aim), Math.sin(@aim)]
  end

  def position
    return [@flight[:x], @flight[:y]] if @flight

    distance = @planet.radius - 1.5
    [@planet.x + (Math.cos(@angle) * distance), @planet.y + (Math.sin(@angle) * distance)]
  end

  def launch(speed)
    x, y = position
    @flight = { x: x, y: y, vx: Math.cos(@angle) * speed, vy: Math.sin(@angle) * speed, spin: 0.0 }
  end

  def render(batch, lighting)
    x, y = position
    base = base_matrix
    SplatRenderer.render(batch, @models[:base], base, x, y, 4.0, SIZE, lighting)
    pivot_x, pivot_y = pivot
    head = head_matrix
    [-BARREL_X, BARREL_X].each_with_index do |side, index|
      offset_x, offset_y, = Rot3.apply(head, side * SIZE, (0.6 - @recoil[index]) * SIZE, 0.0)
      SplatRenderer.render(batch, @models[:barrel], head, pivot_x + offset_x, pivot_y + offset_y, 6.0, SIZE, lighting,
                           glow: 0.15 + (@heat * 1.4))
    end
    SplatRenderer.render(batch, @models[:head], head, pivot_x, pivot_y, 7.0, SIZE * (1.0 + (0.12 * @punch)), lighting)
  end

  private

  def update_flight(dt)
    @flight[:x] += @flight[:vx] * dt
    @flight[:y] += @flight[:vy] * dt
    @flight[:spin] += dt * 9.0
    @recoil = [0.0, 0.0]
  end

  def base_matrix
    spin = @flight ? @flight[:spin] : 0.0
    lean = -@velocity * 0.06
    Rot3.mul(Rot3.rot_z(@angle - (Math::PI / 2) + lean + spin), Rot3.rot_x(TILT))
  end

  def head_matrix
    spin = @flight ? @flight[:spin] * 1.3 : 0.0
    Rot3.mul(Rot3.rot_z(@aim - (Math::PI / 2) + spin), Rot3.rot_x(TILT))
  end

  def pivot
    x, y = position
    offset_x, offset_y, = Rot3.apply(base_matrix, 0.0, PIVOT * SIZE, 0.0)
    [x + offset_x, y + offset_y]
  end

  def wrap(angle)
    angle -= Math::PI * 2 while angle > Math::PI
    angle += Math::PI * 2 while angle < -Math::PI
    angle
  end
end
