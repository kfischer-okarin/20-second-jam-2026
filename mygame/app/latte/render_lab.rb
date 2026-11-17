# The render lab: the set pieces (the cup with poured art on its saucer, the pitcher and the moka pot) on a plain
# tabletop, drawn in one way after the other, to compare how shapes become pixels and how they are lit, without
# the game's palette or post effects. Each variant is one of
#   splats     the baked models drawn as discs, finer discs, upright squares (voxels) or brush strokes
#   raymarched the same SDFs traced per pixel in a shader (raymarch.frag.hlsl), shaded smooth (soft shadows,
#              occlusion, highlights), toon (bands), flat, like clay or snapped to a palette of ramps, with or
#              without lines in ink or in a darker shade of the nearer shape (ink.frag.hlsl)
#   ink splats the way ink-studio draws (InkSplatScene): light baked into ramps, crisp sorted splats resolved
#              from twice the resolution, with contours in ink or in a darker shade
# The light comes from the upper left front, or from behind like the game's sun.
class RenderLab
  ELEVATION = 0.56
  SCALE = 8.0
  CENTER = [0.0, 3.2, 0.0].freeze
  MOKA = [-11.6, 0.0, 0.8, 0.5].freeze
  PITCHER_AT = [11.6, 0.0, 0.8].freeze
  TABLE = [199, 168, 133].freeze
  KEY_LIGHT = [-0.55, 0.75, 0.55].freeze
  BACK_LIGHT = [0.15, 0.42, -0.9].freeze
  VARIANTS = [
    { name: 'SPLATS: DISCS', splats: :disc },
    { name: 'SPLATS: FINE DISCS', splats: :disc, detail: 0.5 },
    { name: 'SPLATS: VOXELS', splats: :square },
    { name: 'SPLATS: BRUSH STROKES', splats: :stroke },
    { name: 'RAYMARCHED: SMOOTH', shading: 0 },
    { name: 'RAYMARCHED: TOON', shading: 1 },
    { name: 'RAYMARCHED: TOON + INK', shading: 1, ink: :black },
    { name: 'RAYMARCHED: FLAT + INK', shading: 2, ink: :black },
    { name: 'RAYMARCHED: CLAY', shading: 3 },
    { name: 'RAYMARCHED: RAMPS + SHADE INK', shading: 4, ink: :shade, palette: InkLook::PALETTE },
    { name: 'INK SPLATS: SHADE CONTOURS', ink_splats: :shade },
    { name: 'INK SPLATS: INK CONTOURS', ink_splats: :ink }
  ].freeze

  attr_reader :backlit

  def initialize(coffee)
    @coffee = coffee
    @index = 0
    @backlit = false
    @lighting = Lighting.new
    @splats = %i[saucer cup moka pitcher].map { |name| [name, SplatBatch.new(:solid, path: :disc)] }.to_h
    @contact = SplatBatch.new(:background)
    @coffee_sprite = LayerSprite.new(:solid)
    @raymarched = LayerSprite.new(:solid, sprite: { x: 0, y: 0, w: PostProcess::W, h: PostProcess::H,
                                                    path: :rt_raymarched, blendmode_enum: 1 })
    @ink_splats = InkSplatScene.new(coffee)
    @ink = LayerSprite.new(:solid, sprite: { x: 0, y: 0, w: PostProcess::W, h: PostProcess::H, path: :rt_ink,
                                             blendmode_enum: 1 })
    @time = 0.0
  end

  def variant
    VARIANTS[@index]
  end

  def label
    text = "#{@index + 1}/#{VARIANTS.length} #{variant[:name]}"
    @backlit ? "#{text} BACKLIT" : text
  end

  def show(index)
    @index = index % VARIANTS.length
  end

  def step(amount)
    show(@index + amount)
  end

  def toggle_light
    @backlit = !@backlit
  end

  # Fills the render targets and returns the batches to draw. Must come before PostProcess#render.
  def render(args)
    @time += 1.0 / 60
    upload_field(args)
    if variant[:ink_splats]
      render_coffee(args)
      @ink_splats.render(args, light_direction, variant[:ink_splats], @coffee_sprite.sprite)
    elsif variant[:splats]
      render_splats(args)
    else
      render_raymarched(args)
    end
  end

  # Neither palette (unless the variant brings its own) nor smoothing nor glare: only the rendering itself
  def grade(post)
    post.palette = variant[:palette] || []
    post.dither = 0.0
    post.smooth = 0
    post.outline = 0.0
    post.bloom = 0.15
    post.bright_threshold = 0.9
    post.vignette = 0.0
    post.saturation = 1.0
    post.exposure = 1.0
    post.shadow_tint = 0.0
    post.veil = 0.0
    post.background_color = TABLE
  end

  private

  def light_direction
    x, y, z = @backlit ? BACK_LIGHT : KEY_LIGHT
    length = Math.sqrt((x * x) + (y * y) + (z * z))
    [x / length, y / length, z / length]
  end

  def upload_field(args)
    pixels = args.pixel_array(:coffee_field)
    pixels.w = CoffeeSurface::N
    pixels.h = CoffeeSurface::N
    pixels.pixels = @coffee.pixels
  end

  # --- Splats ----------------------------------------------------------------------------------------------------

  # Screen position of a world point
  def project(x, y, z)
    cx, cy, cz = CENTER
    [160.0 + ((x - cx) * SCALE),
     90.0 + ((((y - cy) * Math.cos(ELEVATION)) - ((z - cz) * Math.sin(ELEVATION))) * SCALE)]
  end

  def render_splats(args)
    shape = variant[:splats]
    lighting = splat_lighting
    tilt = Rot3.rot_x(ELEVATION)
    detail = variant[:detail]
    draw(:saucer, model(:saucer, detail), tilt, [0.0, 0.0, 0.0], lighting, shape)
    draw(:cup, model(:cup, detail), tilt, [0.0, Cup::BASE_Y, 0.0], lighting, shape)
    mx, my, mz, yaw = MOKA
    draw(:moka, model(:moka_pot, detail), Rot3.mul(tilt, Rot3.rot_y(yaw)), [mx, my, mz], lighting, shape)
    pitcher_rotation = Rot3.rot_y(Pitcher::YAW)
    draw(:pitcher, model(:pitcher, detail), Rot3.mul(tilt, pitcher_rotation), pitcher_tip(pitcher_rotation),
         lighting, shape)
    render_contact_shadows
    render_coffee(args)
    [@contact, @splats[:saucer], @splats[:cup], @coffee_sprite, @splats[:moka], @splats[:pitcher]]
  end

  def model(name, detail)
    detail ? Models.fine(name, detail) : Models.model(name)
  end

  def draw(name, model, matrix, position, lighting, shape)
    batch = @splats[name]
    batch.clear
    batch.path = shape == :square ? :pixel : :disc
    sx, sy = project(*position)
    SplatRenderer.render(batch, model, matrix, sx, sy, 0.0, SCALE, lighting, shape: shape)
  end

  def pitcher_tip(rotation)
    bx, by, bz = Rot3.apply(rotation, *Pitcher::BOTTOM)
    px, py, pz = PITCHER_AT
    [px - bx, py - by, pz - bz]
  end

  # Light in view space: the key light from the upper left front, a cool fill from the sky, a little bounce
  def splat_lighting
    tilt = Rot3.rot_x(ELEVATION)
    lighting = @lighting
    lighting.sun = Rot3.apply(tilt, *light_direction)
    lighting.up = Rot3.apply(tilt, 0.0, 1.0, 0.0)
    lighting.sun_color = [1.0, 0.94, 0.84]
    lighting.ambient = [0.5, 0.54, 0.64]
    lighting.ground = [0.42, 0.36, 0.3]
    lighting.rim = [0.2, 0.18, 0.16]
    lighting.sky = [1.0, 0.98, 0.95]
    lighting.floor = [0.66, 0.56, 0.44]
    lighting.behind = [0.62, 0.6, 0.62]
    lighting
  end

  def render_contact_shadows
    @contact.clear
    [[0.0, 0.0, 15.5, 6.0], [MOKA[0], MOKA[2], 6.5, 3.0], [PITCHER_AT[0], PITCHER_AT[2], 6.5, 3.0]].each do |x, z, w, h|
      sx, sy = project(x, 0.0, z + 0.6)
      @contact.add(sx, sy, w * SCALE, h * SCALE * Math.sin(ELEVATION) * 1.6, 0.0, 120, 92, 70, 170)
    end
  end

  def render_coffee(args)
    radius = @coffee.radius
    width = CoffeeSurface::N / CoffeeSurface::RADIUS_CELLS * radius * SCALE
    height = width * Math.sin(ELEVATION)
    cx, cy = project(0.0, Cup::BASE_Y + @coffee.level, 0.0)
    _rx, rim_y = project(0.0, Cup::BASE_Y + Cup::RIM_Y, 0.0)
    @coffee_sprite.sprite = { x: cx - (width * 0.5), y: cy - (height * 0.5), w: width, h: height, path: :rt_coffee,
                              blendmode_enum: 1 }
    clip = [0.5, 0.5 - ((rim_y - cy) / height), (Cup::RADIUS - Cup::WALL - 0.05) * SCALE / width]
    target = args.outputs[:rt_coffee]
    target.set w: CoffeeSurface::N, h: CoffeeSurface::N, background_color: [0, 0, 0, 0]
    target.primitives << { x: 0, y: 0, w: CoffeeSurface::N, h: CoffeeSurface::N, path: :coffee_field,
                           blendmode_enum: 0 }
    values = [@time, 0.15, CoffeeSurface::RADIUS_CELLS / CoffeeSurface::N, 0.0, clip[0], clip[1], clip[2], clip[2],
              1.0, 0.94, 0.84, 0.7, 0.5, 0.54, 0.64, ELEVATION]
    target.shader = { path: 'shaders/coffee.frag.hlsl', uniforms: floats(values) }
  end

  # --- Raymarched ------------------------------------------------------------------------------------------------

  # The raymarch shader runs where its target is drawn: once in color into rt_raymarched, and once more as
  # geometry for the ink lines, which read both. Both raymarch targets hold the coffee's grid, which the shader
  # reads as t0.
  def render_raymarched(args)
    outputs = args.outputs
    raymarch_target(outputs, :rt_raymarch, 0.0)
    copy(outputs, :rt_raymarched, :rt_raymarch)
    batches = [@raymarched]
    return batches unless variant[:ink]

    raymarch_target(outputs, :rt_raymarch_geometry, 1.0)
    copy(outputs, :rt_geometry, :rt_raymarch_geometry)
    ink = outputs[:rt_ink]
    ink.set w: PostProcess::W, h: PostProcess::H, background_color: [0, 0, 0, 0]
    ink.primitives << { x: 0, y: 0, w: PostProcess::W, h: PostProcess::H, path: :rt_geometry, blendmode_enum: 0 }
    shade = variant[:ink] == :shade ? 1.0 : 0.0
    ink.shader = { path: 'shaders/ink.frag.hlsl', textures: [:rt_raymarched],
                   uniforms: floats([0.16, 0.12, 0.14, 0.55, 0.012, 1.0, shade, 0.0]) }
    batches << @ink
  end

  # Draws source into a target of the screen's size as it is (running source's shader, if it has one)
  def copy(outputs, name, source)
    target = outputs[name]
    target.set w: PostProcess::W, h: PostProcess::H, background_color: [0, 0, 0, 0]
    target.primitives << { x: 0, y: 0, w: PostProcess::W, h: PostProcess::H, path: source, blendmode_enum: 0 }
  end

  def raymarch_target(outputs, name, output)
    n = CoffeeSurface::N
    target = outputs[name]
    target.set w: n, h: n, background_color: [0, 0, 0, 0]
    target.primitives << { x: 0, y: 0, w: n, h: n, path: :coffee_field, blendmode_enum: 0 }
    target.shader = { path: 'shaders/raymarch.frag.hlsl', uniforms: floats(raymarch_uniforms(output)) }
  end

  def raymarch_uniforms(output)
    tip = pitcher_tip(Rot3.rot_y(Pitcher::YAW))
    [SCALE, ELEVATION, PostProcess::W, PostProcess::H,
     *CENTER, 0.0,
     output, variant[:shading], 0.0, 0.0,
     *light_direction, 1.0,
     @coffee.level, @coffee.radius, CoffeeSurface::RADIUS_CELLS / CoffeeSurface::N, 0.0,
     *tip, -Pitcher::YAW,
     MOKA[0], MOKA[1], MOKA[2], -MOKA[3]]
  end

  def floats(values)
    values.map { |value| { type: :float, value: value.to_f } }
  end
end
