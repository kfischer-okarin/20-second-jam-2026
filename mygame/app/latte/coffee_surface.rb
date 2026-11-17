# The surface of the coffee in the cup, as a grid over its disc:
#   foam  milk foam floating on top (0..1): the white of latte art
#   milk  milk mixed in underneath (0..1), which turns the dark crema into a lighter brown
#   wave  ripples, which catch the low sun
# The pour moves them with a surface flow:
# - The stream is a point source. Its outflow falls off as 1/r and is free of divergence away from the source,
#   so it preserves area: a ring of crema pushed outward gets thinner as it widens. That is how latte art makes
#   its thin lines, and how a second blob pushes the first into a crescent (a tulip).
# - Milk poured from high dives under the crema and mixes in; milk poured from just above the surface floats and
#   spreads as foam.
# - A moving stream drags the surface along, which pulls the point of a heart and cuts through it.
# - Near the wall the outward flow stops, so whatever reaches it piles up into a thin ring.
# Part of the flow lingers after the pour stops, and the surface drifts a little longer.
# The level rises with every drop; poured into a full cup, milk runs over the rim (see #take_overflow).
class CoffeeSurface
  N = 52
  CENTER = N * 0.5
  # The disc's radius in cells, leaving a ring of ghost cells around it that copy their nearest cell inside, so
  # that sampling between cells works up to the edge
  RADIUS_CELLS = CENTER - 2.0
  # Area the floating pour spreads per second at full flow, in square cells
  SPREAD = 240.0
  # Fraction of the instantaneous flow that becomes lasting drift per second, and how fast the drift decays
  DRIFT_GAIN = 0.5
  DRIFT_TIME = 0.6
  # The outward flow fades over this many cells before the wall
  WALL_BAND = 3.0
  # How fast foam and milk build up under the stream at full flow
  FOAM_RATE = 9.0
  MILK_RATE = 2.2
  # Centimetres the level rises per second of full flow
  FILL_RATE = 0.075
  # Ripple speed (cells per frame, squared) and damping per frame
  WAVE_SPEED = 0.22
  WAVE_DAMPING = 0.975

  attr_reader :level, :pixels, :mix
  attr_accessor :settled

  def initialize
    @level = Cup::START_LEVEL
    @mix = 0.0
    count = N * N
    @foam = Array.new(count, 0.0)
    @foam_next = Array.new(count, 0.0)
    @milk = Array.new(count, 0.0)
    @milk_next = Array.new(count, 0.0)
    @drift_x = Array.new(count, 0.0)
    @drift_y = Array.new(count, 0.0)
    @wave = Array.new(count, 0.0)
    @wave_last = Array.new(count, 0.0)
    @pixels = Array.new(count, 0xFF80_0000)
    @overflow = 0.0
    @pours = []
    clear_pour
    @drifting = false
    @wave_energy = 0.0
    @rng = Rng.new(31)
    @frame = 0
    build_cells
    pack
  end

  # Radius of the surface in centimetres: the bowl widens as it fills
  def radius
    Cup.inner_radius(@level)
  end

  def full?
    @level >= Cup::FULL_LEVEL
  end

  # Milk landing on the surface this frame at x, z (centimetres from the cup's axis, z towards the viewer).
  # flow is 0..1, fall the height it fell from in centimetres, speed_x/speed_z how fast the stream moves.
  def pour(x, z, flow, fall, speed_x, speed_z)
    @pours << [x, z, flow, fall, speed_x, speed_z]
  end

  # How much milk ran over the rim since the last call, in seconds of full flow
  def take_overflow
    amount = @overflow
    @overflow = 0.0
    amount
  end

  # Foam (0..1) at x, z in centimetres from the cup's axis
  def foam_at(x, z)
    cell = radius / RADIUS_CELLS
    i = (CENTER + (x / cell)).floor.clamp(0, N - 1)
    j = (CENTER + (z / cell)).floor.clamp(0, N - 1)
    @foam[(j * N) + i]
  end

  # How much of the surface is foam, 0..1
  def coverage
    covered = @cells.count { |index| @foam[index] > 0.5 }
    covered.fdiv(@cells.length)
  end

  # Foam and milk are moved every other frame by twice the time, which costs half and blurs their edges less
  # Whatever changes the surface marks it dirty, and only a dirty surface is packed into pixels again
  def update(dt)
    @pours.each do |pour|
      take_pour(*pour, dt)
    end
    @pours.clear
    @frame += 1
    move(dt * 2.0) if @frame.even? && moving?
    ripple if @wave_energy > 0.0005
    pack if @dirty
  end

  private

  def take_pour(x, z, flow, fall, speed_x, speed_z, dt)
    cell = radius / RADIUS_CELLS
    floating = 1.0 - smoothstep(1.2, 4.2, fall)
    @source_x = CENTER + (x / cell)
    @source_y = CENTER + (z / cell)
    @spread += SPREAD * flow * (0.25 + (0.75 * floating))
    drag = 0.55 + (0.45 * (1.0 - flow))
    @drag_x += speed_x / cell * drag
    @drag_y += speed_z / cell * drag
    @drag_radius = 1.6 + (2.2 * flow)
    @poured_frames += 1
    deposit(@source_x, @source_y, flow, floating, fall, dt)
    fill(flow, dt)
    @dirty = true
  end

  def moving?
    @spread.positive? || @drifting
  end

  # Moves the surface by the pours since the last move, averaged, and by what still drifts
  def move(dt)
    frames = [@poured_frames, 1].max
    flow!(dt, @source_x, @source_y, @spread / frames, @drag_x / frames, @drag_y / frames, @drag_radius)
    clear_pour
    @dirty = true
  end

  # The pour of the frames since the surface last moved: where it lands, how it spreads and drags
  def clear_pour
    @source_x = CENTER
    @source_y = CENTER
    @spread = 0.0
    @drag_x = 0.0
    @drag_y = 0.0
    @drag_radius = 1.0
    @poured_frames = 0
  end

  def smoothstep(edge0, edge1, value)
    t = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0)
    t * t * (3.0 - (2.0 * t))
  end

  # Indices of the cells inside the disc with their outward direction, and the ghost cells around it with the
  # cell each one copies
  def build_cells
    @cells = []
    @outward_x = []
    @outward_y = []
    @wall_room = []
    @neighbors = []
    @ghosts = []
    @ghost_sources = []
    N.times do |j|
      N.times do |i|
        dx = i + 0.5 - CENTER
        dy = j + 0.5 - CENTER
        distance = Math.sqrt((dx * dx) + (dy * dy))
        if distance <= RADIUS_CELLS
          add_cell(i, j, dx, dy, distance)
        elsif distance <= RADIUS_CELLS + 2.5
          @ghosts << ((j * N) + i)
          @ghost_sources << nearest_inside(dx, dy, distance)
        end
      end
    end
    inside = @cells.map { |index| [index, true] }.to_h
    @cells.each do |index|
      @neighbors << [index - 1, index + 1, index - N, index + N].map { |other| inside[other] ? other : index }
    end
  end

  def add_cell(column, row, dx, dy, distance)
    @cells << ((row * N) + column)
    length = [distance, 0.001].max
    @outward_x << (dx / length)
    @outward_y << (dy / length)
    @wall_room << ((RADIUS_CELLS - distance) / WALL_BAND).clamp(0.0, 1.0)
  end

  def nearest_inside(dx, dy, distance)
    scale = (RADIUS_CELLS - 0.6) / distance
    i = (CENTER + (dx * scale)).floor
    j = (CENTER + (dy * scale)).floor
    (j * N) + i
  end

  # Foam where the floating milk lands, milk where it dives, a hole punched into the foam by a high stream, and
  # ripples where it hits
  def deposit(source_x, source_y, flow, floating, fall, dt)
    width = 0.9 + (1.6 * flow)
    amounts = [FOAM_RATE * flow * floating * dt, MILK_RATE * flow * (1.0 - floating) * dt,
               3.0 * flow * (1.0 - floating) * dt]
    deposit_around(source_x, source_y, width, *amounts)
    @mix += flow * dt * 0.035
    impact = flow * (0.4 + (0.25 * fall)) * 0.12
    index = (source_y.floor.clamp(0, N - 1) * N) + source_x.floor.clamp(0, N - 1)
    @wave[index] -= impact * (0.6 + @rng.float)
    @wave_energy = 1.0
  end

  # Hot loop over the cells around the stream: foam within width, mixed milk a little wider
  # rubocop:disable-next Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/BlockNesting, Style/MinMaxComparison
  def deposit_around(source_x, source_y, width, foam_amount, milk_amount, punch)
    reach = (width * 2.6).ceil
    narrow = 1.0 / (width * width)
    broad = 1.0 / (width * width * 4.84)
    foam = @foam
    milk = @milk
    column = source_x.floor
    row = source_y.floor
    j = row - reach
    while j <= row + reach
      i = column - reach
      while j >= 0 && j < N && i <= column + reach
        if i >= 0 && i < N
          index = (j * N) + i
          dx = i + 0.5 - source_x
          dy = j + 0.5 - source_y
          r2 = (dx * dx) + (dy * dy)
          near = Math.exp(-r2 * narrow)
          value = (foam[index] + (foam_amount * near)) * (1.0 - (punch * near))
          foam[index] = value > 1.0 ? 1.0 : value
          mixed = milk[index] + (milk_amount * Math.exp(-r2 * broad))
          milk[index] = mixed > 1.0 ? 1.0 : mixed
        end
        i += 1
      end
      j += 1
    end
  end

  def fill(flow, dt)
    rise = flow * FILL_RATE * dt
    room = Cup::FULL_LEVEL - @level
    if rise > room
      @overflow += (rise - [room, 0.0].max) / FILL_RATE
      rise = [room, 0.0].max
    end
    @level += rise
  end

  # Moves foam and milk along the surface flow (semi-Lagrangian: every cell takes what was upstream of it).
  # Hot loop over every cell of the disc.
  # rubocop:disable-next Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Style/NumericPredicate
  def flow!(dt, source_x, source_y, spread, drag_x, drag_y, drag_radius)
    strength = spread / (2.0 * Math::PI)
    soft2 = 1.2
    drag2 = drag_radius * drag_radius
    decay = Math.exp(-dt / DRIFT_TIME)
    gain = DRIFT_GAIN * dt
    cells = @cells
    outward_x = @outward_x
    outward_y = @outward_y
    wall_room = @wall_room
    drift_x = @drift_x
    drift_y = @drift_y
    foam = @foam
    milk = @milk
    foam_next = @foam_next
    milk_next = @milk_next
    n = N
    last = N - 2
    fastest = 0.0
    k = 0
    count = cells.length
    while k < count
      index = cells[k]
      i = index % n
      j = index.idiv(n)
      cx = i + 0.5
      cy = j + 0.5
      ux = 0.0
      uy = 0.0
      if strength > 0.0
        dx = cx - source_x
        dy = cy - source_y
        r2 = (dx * dx) + (dy * dy)
        s = strength / (r2 + soft2)
        ux = dx * s
        uy = dy * s
        w = drag2 / (drag2 + r2)
        w *= w
        ux += drag_x * w
        uy += drag_y * w
      end
      px = (drift_x[index] * decay) + (ux * gain)
      py = (drift_y[index] * decay) + (uy * gain)
      drift_x[index] = px
      drift_y[index] = py
      vx = ux + px
      vy = uy + py
      ox = outward_x[k]
      oy = outward_y[k]
      out = (vx * ox) + (vy * oy)
      if out > 0.0
        cut = out * (1.0 - wall_room[k])
        vx -= cut * ox
        vy -= cut * oy
      end
      speed = (vx * vx) + (vy * vy)
      fastest = speed if speed > fastest
      if speed < 0.0025
        foam_next[index] = foam[index]
        milk_next[index] = milk[index]
        k += 1
        next
      end
      bx = cx - (vx * dt) - 0.5
      by = cy - (vy * dt) - 0.5
      x0 = bx.floor
      y0 = by.floor
      x0 = 0 if x0 < 0
      x0 = last if x0 > last
      y0 = 0 if y0 < 0
      y0 = last if y0 > last
      fx = bx - x0
      fy = by - y0
      fx = 0.0 if fx < 0.0
      fx = 1.0 if fx > 1.0
      fy = 0.0 if fy < 0.0
      fy = 1.0 if fy > 1.0
      a = (y0 * n) + x0
      b = a + 1
      c = a + n
      d = c + 1
      top = foam[a] + ((foam[b] - foam[a]) * fx)
      bottom = foam[c] + ((foam[d] - foam[c]) * fx)
      foam_next[index] = top + ((bottom - top) * fy)
      top = milk[a] + ((milk[b] - milk[a]) * fx)
      bottom = milk[c] + ((milk[d] - milk[c]) * fx)
      milk_next[index] = top + ((bottom - top) * fy)
      k += 1
    end
    @foam = foam_next
    @foam_next = foam
    @milk = milk_next
    @milk_next = milk
    @drifting = fastest > 0.01
    copy_ghosts
  end

  def copy_ghosts
    foam = @foam
    milk = @milk
    ghosts = @ghosts
    sources = @ghost_sources
    k = 0
    count = ghosts.length
    while k < count
      foam[ghosts[k]] = foam[sources[k]]
      milk[ghosts[k]] = milk[sources[k]]
      k += 1
    end
  end

  # Ripples spread as waves and reflect from the wall
  # rubocop:disable-next Metrics/AbcSize
  def ripple
    wave = @wave
    last = @wave_last
    cells = @cells
    neighbors = @neighbors
    speed = WAVE_SPEED
    damping = WAVE_DAMPING
    energy = 0.0
    k = 0
    count = cells.length
    while k < count
      index = cells[k]
      around = neighbors[k]
      h = wave[index]
      laplacian = wave[around[0]] + wave[around[1]] + wave[around[2]] + wave[around[3]] - (4.0 * h)
      value = ((h + h) - last[index] + (speed * laplacian)) * damping
      last[index] = value
      energy += value < 0.0 ? -value : value
      k += 1
    end
    @wave = last
    @wave_last = wave
    @wave_energy = energy / count
    @dirty = true
  end

  # Writes the grid into pixels for the coffee shader: red is foam, green milk, blue the ripples around 0.5
  def pack
    @dirty = false
    pixels = @pixels
    foam = @foam
    milk = @milk
    wave = @wave
    count = N * N
    i = 0
    while i < count
      f = foam[i]
      m = milk[i]
      w = 0.5 + (wave[i] * 2.0)
      w = 0.0 if w < 0.0
      w = 1.0 if w > 1.0
      pixels[i] = 0xFF00_0000 | ((w * 255).to_i << 16) | ((m * 255).to_i << 8) | (f * 255).to_i
      i += 1
    end
  end
end
