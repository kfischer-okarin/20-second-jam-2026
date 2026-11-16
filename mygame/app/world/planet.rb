# The dying planet (its splats come from PlanetBaker). The lava in its cracks glows brighter and wider as the
# end approaches, and plates can break away, which reveals the molten core below.
#
# The rock splats are the most expensive thing in the scene, so each frame rebuilds only every other one of them
# and reuses the other half from the previous frame. The planet turns by a fraction of a pixel per frame, so the
# stale half is invisible.
class Planet
  RADIUS = 44.0
  PLATE_COUNT = 20
  # Crust splats in the cracks belong to this group instead of a plate, so they never break away with one
  CRACK_GROUP = PLATE_COUNT
  TILT = Rot3.mul(Rot3.rot_z(0.42), Rot3.rot_x(0.32))

  attr_reader :x, :y, :plates, :heat, :pulse, :beat, :core_scale

  def initialize(x, y, seed: 11)
    @base_x = x
    @base_y = y
    baker = PlanetBaker.new(seed)
    @plate_centers = baker.plate_centers
    @crust = baker.crust
    @core = baker.core
    @crust_inverse_radius = (0...@crust.count).map { |i|
      1.0 / Math.sqrt((@crust.px[i]**2) + (@crust.py[i]**2) + (@crust.pz[i]**2))
    }
    @rock_count = @crust.group.count { |group| group != CRACK_GROUP }
    @crack_indices = (@rock_count...@crust.count).to_a
    @core_batch = SplatBatch.new(:solid)
    @rock_batches = [SplatBatch.new(:solid), SplatBatch.new(:solid)]
    @crack_batch = SplatBatch.new(:solid)
    @plate_batch = SplatBatch.new(:solid)
    reset
  end

  def reset
    @x = @base_x
    @y = @base_y
    @spin = 0.0
    @time = 0.0
    @frame = 0
    @beat_phase = 0.0
    @beat = 0.0
    @pulse = 0.8
    @heat = 0.3
    @core_scale = 1.0
    @core_brightness = 1.0
    @detached = Array.new(PLATE_COUNT + 1, false)
    @plates = []
    @matrix = rotation
    @rebuild_all = true
  end

  def radius
    RADIUS
  end

  def attached_plate_count
    @detached.count(false) - 1
  end

  def update(dt, doom)
    @time += dt
    @heat = 0.32 + (0.68 * doom)
    @spin += dt * (0.14 + (0.5 * doom * doom))
    heart_rate = 0.8 + (2.6 * doom * doom)
    previous_phase = @beat_phase
    @beat_phase = (@beat_phase + (dt * heart_rate)) % 1.0
    @beat_started = @beat_phase < previous_phase
    @beat = heartbeat(@beat_phase)
    @pulse = 0.72 + (0.28 * @beat)
    tremor = doom * doom * 1.1
    @x = @base_x + (tremor * Math.sin(@time * 47.0))
    @y = @base_y + (tremor * Math.cos(@time * 39.0))
    @matrix = rotation
    update_plates(dt)
  end

  def render(lighting)
    @core_batch.clear
    render_core(@core_batch) if @detached.any? && @core_scale > 0.01
    phases = @rebuild_all ? [0, 1] : [@frame % 2]
    phases.each do |phase|
      @rock_batches[phase].clear
      render_crust(@rock_batches[phase], lighting, phase, @rock_count, 2)
    end
    @rebuild_all = false
    @frame += 1
    @crack_batch.clear
    render_crust(@crack_batch, lighting, @rock_count, @crust.count, 1)
    @plate_batch.clear
    @plates.each { |plate| render_plate(@plate_batch, plate, lighting) }
  end

  # Batches in drawing order. The planet's own splats are drawn around its resting position and shaken by
  # its tremor; flying plates are already where they are.
  def batches
    surface = [@core_batch, *@rock_batches, @crack_batch]
    surface.each do |batch|
      batch.shift_x = @x - @base_x
      batch.shift_y = @y - @base_y
    end
    surface << @plate_batch
  end

  # Breaks off one of the attached plates that face the viewer the most and returns it
  def detach_facing_plate(speed)
    candidates = (0...PLATE_COUNT).reject { |index| @detached[index] }
    return nil if candidates.empty?

    facing = candidates.sort_by { |i| -Rot3.apply(@matrix, *@plate_centers[i])[2] }.first(3)
    detach_plate(facing[rand(facing.length)], speed)
  end

  def beat_started?
    @beat_started
  end

  # Blows every plate off and drains the lava from the cracks. Returns [x, y, normal_x, normal_y] for every
  # other crack splat, as starting points for the molten spray.
  def shatter(speed)
    (0...PLATE_COUNT).each do |index|
      detach_plate(index, speed * rand_range(0.6, 1.5)) unless @detached[index]
    end
    @detached[CRACK_GROUP] = true
    @crack_indices.each_slice(2).map do |index, _|
      x, y, z = Rot3.apply(@matrix, @crust.px[index], @crust.py[index], @crust.pz[index])
      length = Math.sqrt((x * x) + (y * y) + (z * z))
      [@x + x, @y + y, x / length, y / length]
    end
  end

  def core_flare(scale, brightness)
    @core_scale = scale
    @core_brightness = brightness
  end

  # A random glowing crack splat that currently faces the viewer: [x, y, normal_x, normal_y] or nil
  def random_visible_crack
    index = @crack_indices[rand(@crack_indices.length)]
    m = @matrix
    nx, ny, nz = Rot3.apply(m, @crust.nx[index], @crust.ny[index], @crust.nz[index])
    return nil if nz < 0.25

    px, py, = Rot3.apply(m, @crust.px[index], @crust.py[index], @crust.pz[index])
    [@x + px, @y + py, nx, ny]
  end

  private

  def rotation
    Rot3.mul(TILT, Rot3.rot_y(@spin))
  end

  # Two thumps per beat, like a heart
  def heartbeat(phase)
    first = (phase - 0.05) / 0.05
    second = (phase - 0.24) / 0.06
    Math.exp(-first * first) + (0.55 * Math.exp(-second * second))
  end

  def rand_range(min, max)
    min + ((max - min) * rand)
  end

  def normalize(x, y, z)
    length = Math.sqrt((x * x) + (y * y) + (z * z))
    [x / length, y / length, z / length]
  end

  # --- Plates ---------------------------------------------------------------------------------------------

  def detach_plate(index, speed)
    model, cx, cy, cz = plate_model(index)
    length = Math.sqrt((cx * cx) + (cy * cy) + (cz * cz))
    axis = normalize(rand - 0.5, rand - 0.5, rand - 0.5)
    plate = {
      index: index, model: model, x: @x + cx, y: @y + cy, z: cz,
      vx: cx / length * speed, vy: cy / length * speed, vz: (cz / length * speed) + (speed * 0.3),
      axis: axis, angle: 0.0, angular_speed: rand_range(0.8, 2.6) * (rand < 0.5 ? -1 : 1), age: 0.0
    }
    @detached[index] = true
    @rebuild_all = true
    @plates << plate
    plate
  end

  # The plate's splats as the planet is turned right now, around their centroid. Returns the model and the
  # centroid, relative to the planet's center.
  def plate_model(index)
    crust = @crust
    members = (0...crust.count).select { |i| crust.group[i] == index }
    world = members.map { |i| Rot3.apply(@matrix, crust.px[i], crust.py[i], crust.pz[i]) }
    cx, cy, cz = [0, 1, 2].map { |axis| world.sum { |point| point[axis] } / world.length }
    model = SplatModel.new
    members.each_with_index do |i, k|
      nx, ny, nz = Rot3.apply(@matrix, crust.nx[i], crust.ny[i], crust.nz[i])
      model.add(world[k][0] - cx, world[k][1] - cy, world[k][2] - cz, nx, ny, nz,
                crust.cr[i], crust.cg[i], crust.cb[i], crust.aux[i] * 1.6, crust.size[i], 0)
    end
    [model, cx, cy, cz]
  end

  def update_plates(dt)
    @plates.each do |plate|
      plate[:age] += dt
      plate[:x] += plate[:vx] * dt
      plate[:y] += plate[:vy] * dt
      plate[:z] += plate[:vz] * dt
      plate[:angle] += plate[:angular_speed] * dt
    end
    @plates.reject! { |plate| plate[:age] > 6.0 || (plate[:x] - @base_x).abs > 260 || (plate[:y] - @base_y).abs > 190 }
  end

  def render_plate(batch, plate, lighting)
    axis = plate[:axis]
    m = Rot3.axis_angle(axis[0], axis[1], axis[2], plate[:angle])
    cooling = (1.0 - (plate[:age] / 2.5)).clamp(0.0, 1.0)
    SplatRenderer.render(batch, plate[:model], m, plate[:x], plate[:y], plate[:z], 1.0, lighting,
                         glow: cooling * @pulse, cull: -0.3)
  end

  # --- Per-frame rendering of the planet itself -----------------------------------------------------------

  # The crust is a heightfield over a sphere, so splats are culled and shaped by their radial direction, which
  # keeps the coverage hole free on steep slopes; only the lighting uses the true surface normal.
  # Hot loop: comparisons stay operators instead of [a, b].max or #positive?, which allocate or send in mruby.
  # rubocop:disable-next Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/BlockNesting, Style/MinMaxComparison, Style/NumericPredicate
  def render_crust(batch, lighting, start, stop, step)
    m0, m1, m2, m3, m4, m5, m6, m7, m8 = @matrix
    crust = @crust
    px = crust.px
    py = crust.py
    pz = crust.pz
    nx = crust.nx
    ny = crust.ny
    nz = crust.nz
    cr = crust.cr
    cg = crust.cg
    cb = crust.cb
    sizes = crust.size
    groups = crust.group
    cracks = crust.aux
    inverse_radius = @crust_inverse_radius
    detached = @detached
    lx, ly, lz = lighting.sun
    sun_r, sun_g, sun_b = lighting.sun_color
    amb_r, amb_g, amb_b = lighting.ambient
    rim_r, rim_g, rim_b = lighting.rim
    lights = lighting.points_near(@x, @y, RADIUS + 4, receiver: :planet)
    light_count = lights.length
    cx = @base_x
    cy = @base_y
    pulse = @pulse
    threshold = 1.0 - @heat
    rad_to_deg = SplatRenderer::RAD_TO_DEG
    out = batch.data
    j = batch.count * 9
    i = start
    while i < stop
      ox = px[i]
      oy = py[i]
      oz = pz[i]
      sz = (m6 * ox) + (m7 * oy) + (m8 * oz)
      if sz > -3.0 && !detached[groups[i]]
        rx = (m0 * ox) + (m1 * oy) + (m2 * oz)
        ry = (m3 * ox) + (m4 * oy) + (m5 * oz)
        sx = cx + rx
        sy = cy + ry
        ax = nx[i]
        ay = ny[i]
        az = nz[i]
        wx = (m0 * ax) + (m1 * ay) + (m2 * az)
        wy = (m3 * ax) + (m4 * ay) + (m5 * az)
        wz = (m6 * ax) + (m7 * ay) + (m8 * az)

        facing_viewer = sz * inverse_radius[i]
        diffuse = (wx * lx) + (wy * ly) + (wz * lz)
        diffuse = 0.0 if diffuse < 0.0
        rim = 1.0 - (facing_viewer < 0.0 ? 0.0 : facing_viewer)
        rim *= rim * rim
        lr = amb_r + (diffuse * sun_r) + (rim * rim_r)
        lg = amb_g + (diffuse * sun_g) + (rim * rim_g)
        lb = amb_b + (diffuse * sun_b) + (rim * rim_b)

        if light_count > 0
          k = 0
          while k < light_count
            light = lights[k]
            dx = light[0] - sx
            dy = light[1] - sy
            dz = light[2] - sz
            reach = light[6]
            d2 = (dx * dx) + (dy * dy) + (dz * dz)
            if d2 < reach * reach
              d = Math.sqrt(d2) + 0.001
              facing = ((wx * dx) + (wy * dy) + (wz * dz)) / d
              if facing > -0.2
                falloff = 1.0 - (d / reach)
                falloff *= falloff * (facing + 0.2)
                lr += light[3] * falloff
                lg += light[4] * falloff
                lb += light[5] * falloff
              end
            end
            k += 1
          end
        end

        r = cr[i] * lr
        g = cg[i] * lg
        b = cb[i] * lb
        lava = (cracks[i] - threshold) * 3.5
        if lava > 0.0
          lava = 1.0 if lava > 1.0
          hot = lava * pulse
          keep = 1.0 - lava
          r = (r * keep) + (lava * 255.0)
          g = (g * keep) + (lava * (60.0 + (190.0 * hot)))
          b = (b * keep) + (lava * (20.0 + (130.0 * hot * hot)))
        end
        r = 255.0 if r > 255.0
        g = 255.0 if g > 255.0
        b = 255.0 if b > 255.0

        w = sizes[i]
        aspect = facing_viewer < 0.0 ? -facing_viewer : facing_viewer
        aspect = 0.32 if aspect < 0.32
        out[j] = sx
        out[j + 1] = sy
        out[j + 2] = w
        out[j + 3] = w * aspect
        out[j + 4] = (Math.atan2(ry, rx) * rad_to_deg) - 90.0
        out[j + 5] = r
        out[j + 6] = g
        out[j + 7] = b
        out[j + 8] = 255
        j += 9
      end
      i += step
    end
    batch.count = j.idiv(9)
  end

  def render_core(batch)
    m0, m1, m2, m3, m4, m5, m6, m7, m8 = @matrix
    core = @core
    px = core.px
    py = core.py
    pz = core.pz
    sizes = core.size
    groups = core.group
    phases = core.aux
    detached = @detached
    scale = @core_scale
    brightness = @core_brightness * @pulse
    time = @time * 2.4
    cx = @base_x
    cy = @base_y
    out = batch.data
    j = batch.count * 9
    i = 0
    n = core.count
    while i < n
      if detached[groups[i]]
        ox = px[i]
        oy = py[i]
        oz = pz[i]
        if (m6 * ox) + (m7 * oy) + (m8 * oz) > -4.0
          # Cooled dark red skins drift over yellow-hot magma
          churn = 0.5 + (0.5 * Math.sin(time + phases[i]))
          heat = churn * churn * brightness
          r = 110.0 + (230.0 * heat)
          g = 18.0 + (220.0 * heat * heat)
          b = 12.0 + (130.0 * heat * heat * heat)
          r = 255.0 if r > 255.0
          g = 255.0 if g > 255.0
          b = 255.0 if b > 255.0
          w = sizes[i] * scale
          out[j] = cx + (((m0 * ox) + (m1 * oy) + (m2 * oz)) * scale)
          out[j + 1] = cy + (((m3 * ox) + (m4 * oy) + (m5 * oz)) * scale)
          out[j + 2] = w
          out[j + 3] = w
          out[j + 4] = 0.0
          out[j + 5] = r
          out[j + 6] = g
          out[j + 7] = b
          out[j + 8] = 255
          j += 9
        end
      end
      i += 1
    end
    batch.count = j.idiv(9)
  end
end
