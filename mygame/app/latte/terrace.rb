# Everything on and around the table: the world beyond it, the table, the saucer, cup and coffee, the moka pot,
# the pitcher with its stream, spilled milk, shadows and steam. It routes the milk to wherever it lands, keeps
# the light, and draws it all in order (there is no depth buffer, see guides/rendering.md):
#   background  sky, meadow, table, the table's shadows
#   solid       puddles on the table, saucer, puddles on it, its shadows, cup, drips, coffee, its shadows,
#               moka pot, stream, pitcher, splashes
#   glow        sun, wave, glints, steam
# In the ink look (see InkPieces) the saucer, the cup and the moka pot are one sprite, so what lies on them comes
# after all three, and the light is a sun from the left that stays put.
class Terrace
  MOKA_POSITION = [-10.6, 0.0, 3.6].freeze
  MOKA_YAW = 0.5
  # What a shadow on the table multiplies its color by in the ink look: from its light tone to its shadow tone
  INK_SHADOW = [176.0 / 214, 128.0 / 168, 98.0 / 124].freeze
  # Elevation of the sun (radians) as the wave comes: shadows grow long
  SUN_HIGH = 0.68
  SUN_LOW = 0.13

  attr_reader :view, :coffee, :pitcher, :spills, :world, :cup_offset, :light, :style
  # progress of the light: 0 before the supernova, 1 when the wave reached the table, 2 at the cup
  attr_accessor :light_progress, :cup_glow, :cup_lift, :flash, :hidden

  def initialize
    @view = View.new
    @lighting = Lighting.new
    @table = Table.new
    @world = World.new
    @coffee = CoffeeSurface.new
    @pitcher = Pitcher.new
    @spills = Spills.new
    @shadows = Shadows.new
    @steam = Steam.new
    @models = { cup: Models.cup, saucer: Models.saucer, moka: Models.moka_pot, pitcher: Models.pitcher }
    @splat_casters = {
      cup: Shadows.sample(@models[:cup], 0.3, coffee: false), saucer: Shadows.sample(@models[:saucer], 0.38),
      moka: Shadows.sample(@models[:moka], 0.3), pitcher: Shadows.sample(@models[:pitcher], 0.28)
    }
    @batches = %i[saucer cup moka pitcher stream].map { |name| [name, SplatBatch.new(:solid, path: :disc)] }.to_h
    @coffee_sprite = LayerSprite.new(:solid, sprite: { path: :rt_coffee, blendmode_enum: 1 })
    @light_progress = 0.0
    @cup_glow = 0.0
    @cup_lift = nil
    @flash = 0.0
    @hidden = {}
    @time = 0.0
    @static_key = nil
    @pour_gain = 0.0
    @splash_at = nil
    @splash_sound = 0.0
    self.style = Styles.default
    update_light
  end

  # How loud the pour is (0..1), and whether milk just splashed somewhere it should not
  attr_reader :pour_gain, :splash_sound

  # Ink lines around the objects and cel shading on them, or the ink look, see Styles
  def style=(style)
    @style = style
    %i[saucer cup moka pitcher].each do |name|
      @batches[name].ink = style[:ink]
    end
    @ink ||= InkPieces.new(ink_placement) if ink?
    @table.plain = ink? ? InkLook::PALETTE[InkLook::TABLE] : nil
    @shadows.hard = ink?
    @shadows.tint = ink? ? INK_SHADOW : Shadows::TINT
    @casters = ink? ? ink_casters : @splat_casters
  end

  # Hard shadows need smooth edges, so they are cast by every splat: the finer ones of the pieces that stand still
  def ink_casters
    @ink_casters ||= begin
      static = @ink.casters
      pitcher = @models[:pitcher]
      { cup: static[:cup], saucer: static[:saucer], moka: static[:moka_pot],
        pitcher: Shadows.sample(pitcher, 0.28, samples: pitcher.count) }
    end
  end

  def ink?
    @style[:ink_look]
  end

  def update(dt, controls)
    @time += dt
    @cup_anchor = @view.point(0.0, 0.0, 0.0)
    update_light
    @pitcher.update(dt, controls, surface_y)
    pour(dt)
    @coffee.update(dt)
    @spills.update(dt, @splash_at)
    @steam.wind = (@light_progress - 0.55).clamp(0.0, 1.0)
    @steam.update(dt) do |rng|
      steam_source(rng)
    end
    @world.wind = (@light_progress * 0.6).clamp(0.0, 1.0)
  end

  # World height of the coffee's surface
  def surface_y
    Cup::BASE_Y + @coffee.level
  end

  # Where the stream lands: [world height, receiver]
  def floor_at(x, z)
    if @cup_lift.nil?
      distance = Math.sqrt((x * x) + (z * z))
      return [surface_y, :coffee] if distance < @coffee.radius
      return [Cup::BASE_Y + Cup::RIM_Y + Cup::WALL, :rim] if distance < Cup::RADIUS + Cup::WALL + 0.05
      return [Cup::SAUCER_Y, :saucer] if distance < Cup::SAUCER_RADIUS
    end
    [0.0, :table]
  end

  # Fills the render targets that the layers draw and returns the batches in drawing order. Must come before
  # PostProcess#render in the tick.
  def render(args)
    @cup_anchor = @view.point(0.0, 0.0, 0.0)
    render_static
    ink? ? render_ink(args.outputs) : render_pitcher
    render_stream
    render_coffee(args)
    @shadows.clear_moving
    cast_pitcher_shadow unless @hidden[:pitcher]
    @shadows.render_targets(args.outputs)
    @world.render(@view, @time)
    @table.render(@view, @table_light, @glare, bleach_z)
    @spills.render(->(x, y, z) { @view.point(x, y, z) }, ->(x, y, z) { cup_point(x, y, z) }, @table_light)
    batches
  end

  # [screen_x, screen_y, scale, elevation] of a point near the cup, with the cup's weak perspective
  def cup_point(x, y, z)
    ax, ay, scale, elevation = @cup_anchor
    [ax + (x * scale), ay + (((y * Math.cos(elevation)) - (z * Math.sin(elevation))) * scale), scale, elevation]
  end

  # Screen rectangle of the coffee's surface, for the afterimage
  def coffee_rect
    @coffee_sprite.sprite.slice(:x, :y, :w, :h)
  end

  # [screen_x, screen_y, scale, elevation] of the bottom of the cup's foot. Lifted towards the eye in the ending,
  # it grows.
  def cup_frame
    lifted_point(*cup_position)
  end

  # View#point for something lifted off the table towards the eye, which grows as it comes closer
  def lifted_point(x, y, z)
    sx, sy, scale, elevation = @view.point(x, y, z)
    lift = (y - Cup::BASE_Y) * Math.sin(elevation)
    [sx, sy, scale * @view.height / [@view.height - lift, 4.0].max, elevation]
  end

  # Lighting seen from an elevation: the sun ahead of the eye, low, so everything is lit from behind
  def light_for(elevation)
    lighting = @lighting
    a = @sun_elevation + elevation
    lighting.sun = [0.0, Math.sin(a), -Math.cos(a)]
    lighting.up = [0.0, Math.cos(elevation), Math.sin(elevation)]
    lighting.sun_color = @sun_color
    lighting.ambient = @ambient
    lighting.ground = @ground
    lighting.rim = @rim
    # Metal reflects the bright sky ahead, the sunlit table below it and the shaded terrace behind the eye. The
    # palette's only neutrals are blue-grays, so reflections are either cool or clearly warm: a warm gray would
    # dither into purple.
    lighting.sky = [1.12 + (@light_progress * 0.3), 1.1 + (@light_progress * 0.3), 1.08 + (@light_progress * 0.35)]
    lighting.floor = [0.88, 0.56, 0.38]
    lighting.behind = [0.48, 0.55, 0.7]
    lighting
  end

  private

  def batches
    list = [@world.sky, @world.back, @world.meadow, *@table.batches, @shadows.table_sprite, @spills.table_batch]
    ink? ? add_ink_batches(list) : add_splat_batches(list)
    list << @spills.splashes.render << @world.glow << @steam.render
    tilt = @view.tilt
    list.each do |batch|
      batch.shift_y = tilt
    end
    list
  end

  def add_splat_batches(list)
    list << @batches[:saucer] << @spills.saucer_batch << @shadows.saucer_sprite unless @hidden[:saucer]
    list << @batches[:cup] << @spills.drip_batch << @coffee_sprite << @shadows.coffee_sprite unless @hidden[:cup]
    list << @batches[:moka] << @batches[:stream]
    list << @batches[:pitcher] unless @hidden[:pitcher]
  end

  # The shadows on the saucer would darken the cup and the table's shadows behind it too, now that the saucer and
  # the cup are one sprite, so the pitcher shadows only the table and the coffee
  def add_ink_batches(list)
    list << @ink.static_sprite
    list << @spills.saucer_batch unless @hidden[:saucer]
    list << @spills.drip_batch << @coffee_sprite << @shadows.coffee_sprite unless @hidden[:cup]
    list << @batches[:stream]
    list << @ink.pitcher_sprite unless @hidden[:pitcher]
  end

  # The light of the afternoon, then of the wave: the sun sinks towards the horizon, so shadows grow, and its
  # light grows stronger and whiter
  def update_light
    p = @light_progress.clamp(0.0, 2.0)
    @sun_elevation = SUN_HIGH + ((SUN_LOW - SUN_HIGH) * ((p * 0.5).clamp(0.0, 1.0)**0.8))
    strength = 1.0 + (p * 0.45)
    white = (p * 0.4).clamp(0.0, 1.0)
    @sun_color = [1.25 * strength, (0.92 + (white * 0.3)) * strength, (0.66 + (white * 0.55)) * strength]
    @ambient = [0.52 + (p * 0.12), 0.54 + (p * 0.12), 0.66 + (p * 0.1)]
    @ground = [0.42, 0.3, 0.22]
    @rim = [0.9 + (p * 0.5), 0.62 + (p * 0.5), 0.38 + (p * 0.5)]
    sine = Math.sin(@sun_elevation)
    @table_light = Array.new(3) { |c| (@ambient[c] * 0.75) + (@sun_color[c] * sine * 0.75) }
    @glare = 0.08 + (p * 0.25)
    @shadows.strength = ink? ? 1.0 : (0.5 + (p * 0.18)).clamp(0.0, 0.85)
    @world.supernova = p.positive? ? [p * 4.0, 1.0].min : 0.0
    @world.wave = p
  end

  # The wave bleaches the table from its far edge up to just behind the cup
  def bleach_z
    return View::TABLE_FAR_Z - 10.0 if @light_progress <= 1.0

    View::TABLE_FAR_Z + ([@light_progress - 1.0, 1.0].min * 10.0)
  end

  def pour(dt)
    @splash_at = nil
    gain = 0.0
    @splash_sound = 0.0
    @pitcher.landed { |x, z| floor_at(x, z)[0] }.each do |x, z, flow, fall, speed_x, speed_z, ground|
      receiver = floor_at(x, z)[1]
      gain = [gain, flow].max
      case receiver
      when :coffee then @coffee.pour(x, z, flow, fall, speed_x, speed_z)
      when :rim then @spills.drip(Math.atan2(x, z), flow * dt * 1.5)
      else @spills.land(x, z, flow, fall, receiver, dt)
      end
      next if receiver == :coffee

      @splash_at = receiver == :table ? @view.point(x, ground, z) : cup_point(x, ground, z)
      @splash_sound += flow * dt
    end
    overflow = @coffee.take_overflow
    @spills.drip(Math.atan2(@pitcher.x, @pitcher.z), overflow * 1.5) if overflow.positive?
    @pour_gain = gain
  end

  # The saucer, the cup and the moka pot stand still, so they are drawn again (and cast their shadows again)
  # only when the view or the light changed noticeably. InkPieces draws them in the ink look.
  def render_static
    key = [@view.pitch.round(3), @view.height.round(2), (@light_progress * 30).round, @cup_glow.round(2), @cup_lift,
           @flash.round(2), @style[:name]]
    return if key == @static_key

    @static_key = key
    unless ink?
      render_model(:saucer, Rot3::IDENTITY, [0.0, 0.0, 0.0])
      render_model(:cup, Rot3::IDENTITY, cup_position)
      render_model(:moka, Rot3.rot_y(MOKA_YAW), MOKA_POSITION)
    end
    cast_static_shadows
  end

  # Where InkPieces lights the pieces that stand still
  def ink_placement
    { saucer: [Rot3::IDENTITY, [0.0, 0.0, 0.0]], cup: [Rot3::IDENTITY, [0.0, Cup::BASE_Y, 0.0]],
      moka_pot: [Rot3.rot_y(MOKA_YAW), MOKA_POSITION] }
  end

  def render_ink(outputs)
    frames = {}
    frames[:saucer] = @view.point(0.0, 0.0, 0.0) unless @hidden[:saucer]
    frames[:cup] = cup_frame unless @hidden[:cup]
    frames[:moka_pot] = @view.point(*MOKA_POSITION)
    pitcher = [@view.point(@pitcher.x, @pitcher.y, @pitcher.z), @pitcher.rotation] unless @hidden[:pitcher]
    @ink.render(outputs, @view.focal, frames, pitcher)
  end

  def cup_position
    return [0.0, Cup::BASE_Y, 0.0] unless @cup_lift

    @cup_lift
  end

  def render_model(name, rotation, position)
    batch = @batches[name]
    batch.clear
    return if @hidden[name]

    sx, sy, scale, elevation = name == :cup ? cup_frame : @view.point(*position)
    matrix = Rot3.mul(Rot3.rot_x(elevation), rotation)
    flash = name == :cup ? @flash + (@cup_glow * 0.15) : @flash
    SplatRenderer.render(batch, @models[name], matrix, sx, sy, 0.0, scale, light_for(elevation),
                         flash: flash, bands: @style[:bands], reflect: @style.fetch(:gloss, 1.0))
  end

  def render_pitcher
    batch = @batches[:pitcher]
    batch.clear
    return if @hidden[:pitcher]

    sx, sy, scale, elevation = @view.point(@pitcher.x, @pitcher.y, @pitcher.z)
    matrix = Rot3.mul(Rot3.rot_x(elevation), @pitcher.rotation)
    SplatRenderer.render(batch, @models[:pitcher], matrix, sx, sy, 0.0, scale, light_for(elevation),
                         flash: @flash, bands: @style[:bands], reflect: @style.fetch(:gloss, 1.0))
  end

  # The stream from the spout down through the falling parcels, cut off where the cup's rim hides it
  def render_stream
    batch = @batches[:stream]
    batch.clear
    parcels = @pitcher.parcels
    return if parcels.empty?

    r, g, b = stream_color
    points = parcels.reverse.map { |parcel| [parcel[0], parcel[1], parcel[2], parcel[6]] }
    points.unshift([@pitcher.x, @pitcher.y, @pitcher.z, @pitcher.flow]) if @pitcher.flow.positive?
    points.each_cons(2) do |(x1, y1, z1, f1), (x2, y2, z2, f2)|
      stream_segment(batch, [x1, y1, z1, f1], [x2, y2, z2, f2], r, g, b)
    end
  end

  # Milk in the light, or the milk's light tone in the ink look
  def stream_color
    return InkLook::PALETTE[InkLook::TWO_TONES[:milk][:ramp].last] if ink?

    light = light_for(@cup_anchor[3])
    Array.new(3) { |c| (Models::MILK[c] * (light.ambient[c] + (light.rim[c] * 0.5))).clamp(0, 255) }
  end

  def stream_segment(batch, start, finish, r, g, b)
    sx1, sy1, scale = @view.point(start[0], start[1], start[2])
    sx2, sy2, = @view.point(finish[0], finish[1], finish[2])
    steps = [(Math.sqrt(((sx2 - sx1)**2) + ((sy2 - sy1)**2)) / 1.2).ceil, 1].max
    steps.times do |i|
      t = i.fdiv(steps)
      x = start[0] + ((finish[0] - start[0]) * t)
      y = start[1] + ((finish[1] - start[1]) * t)
      z = start[2] + ((finish[2] - start[2]) * t)
      sx = sx1 + ((sx2 - sx1) * t)
      sy = sy1 + ((sy2 - sy1) * t)
      next if behind_rim?(x, y, z, sx, sy)

      flow = start[3] + ((finish[3] - start[3]) * t)
      width = [(0.1 + (0.3 * flow)) * scale, 1.3].max
      batch.add(sx, sy, width, width, 0.0, r, g, b, 255)
    end
  end

  # Below the rim inside the cup, the front of the cup hides the stream
  def behind_rim?(x, y, z, screen_x, screen_y)
    return false if y > Cup::BASE_Y + Cup::RIM_Y || (x * x) + (z * z) > Cup::RADIUS**2

    ax, _ay, scale, elevation = @cup_anchor
    _rx, rim_y, = cup_point(0.0, Cup::BASE_Y + Cup::RIM_Y, 0.0)
    radius = (Cup::RADIUS - Cup::WALL) * scale
    across = ((screen_x - ax) / radius).clamp(-1.0, 1.0)
    front = rim_y - (radius * Math.sin(elevation) * Math.sqrt(1.0 - (across * across)))
    screen_y < front
  end

  # The coffee's grid goes into rt_coffee through the coffee shader; the sprite draws it as an ellipse
  def render_coffee(args)
    pixels = args.pixel_array(:coffee_field)
    pixels.w = CoffeeSurface::N
    pixels.h = CoffeeSurface::N
    pixels.pixels = @coffee.pixels
    target = args.outputs[:rt_coffee]
    target.set w: CoffeeSurface::N, h: CoffeeSurface::N, background_color: [0, 0, 0, 0]
    target.primitives << { x: 0, y: 0, w: CoffeeSurface::N, h: CoffeeSurface::N, path: :coffee_field,
                           blendmode_enum: 0 }
    position_coffee_sprite
    target.shader = { path: 'shaders/coffee.frag.hlsl', uniforms: coffee_uniforms }
  end

  def position_coffee_sprite
    cx, foot_y, scale, elevation = cup_frame
    rise = Math.cos(elevation) * scale
    cy = foot_y + (@coffee.level * rise)
    width = CoffeeSurface::N / CoffeeSurface::RADIUS_CELLS * @coffee.radius * scale
    height = width * Math.sin(elevation)
    sprite = @coffee_sprite.sprite
    sprite[:x] = cx - (width * 0.5)
    sprite[:y] = cy - (height * 0.5)
    sprite[:w] = width
    sprite[:h] = height
    rim_y = foot_y + (Cup::RIM_Y * rise)
    @clip = [0.5, 0.5 - ((rim_y - cy) / height), (Cup::RADIUS - Cup::WALL - 0.05) * scale / width]
    @coffee_elevation = elevation
  end

  def coffee_uniforms
    center_x, center_y, radius = @clip
    values = [@time, @coffee.mix.clamp(0.0, 0.6), CoffeeSurface::RADIUS_CELLS / CoffeeSurface::N, @cup_glow,
              center_x, center_y, radius, radius,
              *@sun_color, @sun_elevation,
              *@ambient, @coffee_elevation,
              ink? ? 1.0 : 0.0, 0.0, 0.0, 0.0]
    values.map { |value| { type: :float, value: value.to_f } }
  end

  # Towards the sun: ahead of the eye, or from the left in the ink look
  def sun_direction
    return InkPieces::SUN if ink?

    [0.0, Math.sin(@sun_elevation), -Math.cos(@sun_elevation)]
  end

  def shadow_scene
    ax, ay, scale, elevation = @cup_anchor
    lx, ly, lz = sun_direction
    {
      run_x: -lx / ly, run_z: -lz / ly, stretch: ink? ? 1.0 : (1.0 / ly).clamp(1.0, 3.0), level: surface_y,
      coffee_radius: @coffee.radius, saucer_y: Cup::SAUCER_Y, saucer_radius: Cup::SAUCER_RADIUS - 0.4,
      cup: [ax, ay, scale, Math.cos(elevation), Math.sin(elevation)],
      camera: [@view.height, @view.distance, Math.cos(@view.pitch), Math.sin(@view.pitch), @view.focal]
    }
  end

  # In the ink look the pieces' shadows on each other are part of how InkPieces lit them
  def cast_static_shadows
    @shadows.clear_static
    scene = shadow_scene
    table_only = ink?
    [[:saucer, Rot3::IDENTITY, [0.0, 0.0, 0.0]], [:cup, Rot3::IDENTITY, cup_position],
     [:moka, Rot3.rot_y(MOKA_YAW), MOKA_POSITION]].each do |name, rotation, position|
      next if @hidden[name]

      @shadows.cast_static(@casters[name], rotation, position, scene, table_only: table_only)
    end
  end

  def cast_pitcher_shadow
    @shadows.cast_moving(@casters[:pitcher], @pitcher.rotation, [@pitcher.x, @pitcher.y, @pitcher.z], shadow_scene)
  end

  def steam_source(rng)
    angle = rng.range(0.0, 6.28)
    distance = Math.sqrt(rng.float) * @coffee.radius * 0.85
    x, y, scale = cup_point(Math.cos(angle) * distance, surface_y, Math.sin(angle) * distance)
    [x, y, scale]
  end
end
