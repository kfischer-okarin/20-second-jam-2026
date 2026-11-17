# The render lab's set pieces drawn the way ink-studio draws its dioramas (see RenderLab):
# - every splat is lit once, at bake time, into a color of its material's ramp (RampLighting), with soft shadows
#   and occlusion traced through the scene, so nothing is lit per frame
# - the table is splats too, so the pieces cast their shadows onto it
# - the splats are crisp ellipses (the :hard texture), drawn from far to near at twice the screen's resolution, once
#   in their colors and once as depth
# - resolve.frag.hlsl turns each 2 by 2 block into one pixel: the color most of the block has, and a contour where
#   a nearer shape ends, in ink or in a darker shade of that shape
# Nothing moves, so the bake and the projection happen once per light.
class InkSplatScene
  TABLE_SPACING = 0.6
  # How far the table reaches around the pieces, in centimetres
  TABLE = [-22.0, -28.0, 22.0, 18.0].freeze
  SUPER = 2
  # The crisp ellipse of the :hard texture covers less of its sprite than a soft splat, so splats are drawn this
  # much larger to close the gaps between them
  COVER = 1.35

  def initialize(coffee)
    @coffee = coffee
    @far = [SplatBatch.new(:solid, path: :hard), SplatBatch.new(:solid, path: :hard)]
    @near = [SplatBatch.new(:solid, path: :hard), SplatBatch.new(:solid, path: :hard)]
    @resolve = LayerSprite.new(:solid, sprite: { x: 0, y: 0, w: PostProcess::W, h: PostProcess::H,
                                                 path: :rt_ink_resolve, blendmode_enum: 1 })
    @baked_for = nil
    upload_palette
  end

  # Fills the targets the resolve reads and returns what to draw in the solid layer. contour is :ink or :shade.
  # Nothing moves, so the splats are drawn into their targets only after a bake, or every frame when cache is off;
  # a render target that is not drawn again keeps what it holds.
  def render(args, light, contour, coffee_sprite, cache: true)
    if @baked_for != light
      bake(light)
      @drawn = false
    end
    w = PostProcess::W * SUPER
    h = PostProcess::H * SUPER
    draw_splats(args.outputs, coffee_sprite, w, h) unless cache && @drawn
    resolve(args.outputs, contour, w, h)
    [@resolve]
  end

  private

  def draw_splats(outputs, coffee_sprite, w, h)
    coffee = coffee_sprite.merge(x: coffee_sprite[:x] * SUPER, y: coffee_sprite[:y] * SUPER,
                                 w: coffee_sprite[:w] * SUPER, h: coffee_sprite[:h] * SUPER)
    draw_target(outputs, :rt_ink_color, [@far[0], coffee, @near[0]], w, h)
    draw_target(outputs, :rt_ink_depth, [@far[1], coffee_depth(coffee), @near[1]], w, h)
    @drawn = true
  end

  def upload_palette
    pixels = Array.new(PostProcess::PALETTE_SLOTS, 0xFF00_0000)
    InkLook::PALETTE.each_with_index do |(r, g, b), i|
      pixels[i] = 0xFF00_0000 | (b << 16) | (g << 8) | r
    end
    pixel_array = $gtk.args.pixel_array(:ink_palette)
    pixel_array.w = PostProcess::PALETTE_SLOTS
    pixel_array.h = 1
    pixel_array.pixels = pixels
  end

  # Cleared to transparent black: what is drawn into it is stored premultiplied, and the resolve divides by alpha
  def draw_target(outputs, name, primitives, w, h)
    target = outputs[name]
    target.set w: w, h: h, background_color: [0, 0, 0, 0]
    target.primitives << primitives
  end

  # The coffee lies flat at its own depth: an ellipse in the depth target (the :hard texture covers a little less
  # than its sprite, about as much as the coffee covers of its own)
  def coffee_depth(coffee)
    depth = depth_value(view_depth(0.0, Cup::BASE_Y + @coffee.level, 0.0))
    coffee.merge(path: :hard, r: depth, g: depth, b: depth, a: 255, blendmode_enum: 1)
  end

  def resolve(outputs, contour, w, h)
    target = outputs[:rt_ink_resolve]
    target.set w: w, h: h, background_color: [0, 0, 0, 0]
    target.primitives << { x: 0, y: 0, w: w, h: h, path: :rt_ink_color, blendmode_enum: 0 }
    values = [InkLook::PALETTE.length, 0.035, contour == :ink ? 1.0 : 2.0, 0.0, 0.11, 0.08, 0.12, 0.0]
    target.shader = { path: 'shaders/resolve.frag.hlsl', textures: %i[rt_ink_depth ink_palette],
                      uniforms: values.map { |value| { type: :float, value: value.to_f } } }
  end

  # --- Baking ----------------------------------------------------------------------------------------------------

  def bake(light)
    lighting = RampLighting.new(field, sun: light, view: view_direction, seed: 5)
    splats = []
    pieces.each do |name, rotation, position|
      add_model(splats, Models.model(name), rotation, position, lighting)
    end
    add_table(splats, lighting, field)
    splats = splats.sort_by { |splat| splat[0] }
    split = view_depth(0.0, Cup::BASE_Y + @coffee.level, 0.0)
    fill(@far, splats.select { |splat| splat[0] <= split })
    fill(@near, splats.select { |splat| splat[0] > split })
    @baked_for = light
  end

  def pieces
    mx, my, mz, yaw = RenderLab::MOKA
    pitcher = Rot3.rot_y(Pitcher::YAW)
    [[:saucer, Rot3::IDENTITY, [0.0, 0.0, 0.0]], [:cup, Rot3::IDENTITY, [0.0, Cup::BASE_Y, 0.0]],
     [:moka_pot, Rot3.rot_y(yaw), [mx, my, mz]], [:pitcher, pitcher, pitcher_tip(pitcher)]]
  end

  def pitcher_tip(rotation)
    bx, by, bz = Rot3.apply(rotation, *Pitcher::BOTTOM)
    px, py, pz = RenderLab::PITCHER_AT
    [px - bx, py - by, pz - bz]
  end

  def field
    radii = { saucer: 7.8, cup: 8.4, moka_pot: 9.8, pitcher: 10.6 }
    parts = { saucer: :saucer_parts, cup: :cup_parts, moka_pot: :moka_pot_parts, pitcher: :pitcher_parts }
    SetPieceField.new(pieces.map { |name, rotation, position|
      [Models.send(parts[name]), rotation, position, radii[name]]
    })
  end

  # A splat is [depth, screen x, y, width, height, angle, palette index, depth value], at twice the resolution
  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def add_model(splats, model, rotation, position, lighting)
    m0, m1, m2, m3, m4, m5, m6, m7, m8 = rotation
    ox, oy, oz = position
    cos_e = Math.cos(RenderLab::ELEVATION)
    sin_e = Math.sin(RenderLab::ELEVATION)
    model.count.times do |i|
      ax = model.nx[i]
      ay = model.ny[i]
      az = model.nz[i]
      nx = (m0 * ax) + (m1 * ay) + (m2 * az)
      ny = (m3 * ax) + (m4 * ay) + (m5 * az)
      nz = (m6 * ax) + (m7 * ay) + (m8 * az)
      view_y = (cos_e * ny) - (sin_e * nz)
      view_z = (sin_e * ny) + (cos_e * nz)
      next if view_z < -0.12

      px = model.px[i]
      py = model.py[i]
      pz = model.pz[i]
      x = ox + (m0 * px) + (m1 * py) + (m2 * pz)
      y = oy + (m3 * px) + (m4 * py) + (m5 * pz)
      z = oz + (m6 * px) + (m7 * py) + (m8 * pz)
      material = InkLook.material_of(model.cr[i], model.cg[i], model.cb[i])
      color = lighting.color(material, x, y, z, nx, ny, nz)
      w = model.size[i] * RenderLab::SCALE * SUPER * COVER
      aspect = view_z.abs.clamp(0.32, 1.0)
      angle = (Math.atan2(view_y, nx) * SplatRenderer::RAD_TO_DEG) - 90.0
      splats << splat(x, y, z, w, w * aspect, angle, color)
    end
  end

  def splat(x, y, z, w, h, angle, color)
    sx, sy = project(x, y, z)
    depth = view_depth(x, y, z)
    [depth, sx * SUPER, sy * SUPER, w, h, angle, color, depth_value(depth)]
  end

  # Flat splats are drawn without a depth test, so table splats under a piece could paint over it: they are left
  # out, like everything hidden inside a solid
  def add_table(splats, lighting, field)
    left, back, right, front = TABLE
    w = TABLE_SPACING * 3.0 * RenderLab::SCALE * SUPER
    flat = Math.sin(RenderLab::ELEVATION)
    rng = Rng.new(17)
    z = back
    while z < front
      x = left
      while x < right
        jx = x + rng.range(-0.2, 0.2)
        jz = z + rng.range(-0.2, 0.2)
        x += TABLE_SPACING
        next if field.distance_to_pieces(jx, 0.0, jz) < TABLE_SPACING * 0.8

        color = lighting.color(InkLook::MATERIALS[:table], jx, 0.0, jz, 0.0, 1.0, 0.0)
        splats << splat(jx, 0.0, jz, w, w * flat, 0.0, color)
      end
      z += TABLE_SPACING
    end
  end

  def fill(batches, splats)
    color_batch, depth_batch = batches
    color_batch.clear
    depth_batch.clear
    splats.each do |splat|
      _depth, x, y, w, h, angle, index, value = splat
      r, g, b = InkLook::PALETTE[index]
      color_batch.add(x, y, w, h, angle, r, g, b, 255)
      depth_batch.add(x, y, w, h, angle, value, value, value, 255)
    end
  end

  # --- The lab's camera ------------------------------------------------------------------------------------------

  def project(x, y, z)
    cx, cy, cz = RenderLab::CENTER
    e = RenderLab::ELEVATION
    [160.0 + ((x - cx) * RenderLab::SCALE),
     90.0 + ((((y - cy) * Math.cos(e)) - ((z - cz) * Math.sin(e))) * RenderLab::SCALE)]
  end

  # Larger is nearer the eye
  def view_depth(_x, y, z)
    _cx, cy, cz = RenderLab::CENTER
    e = RenderLab::ELEVATION
    (Math.sin(e) * (y - cy)) + (Math.cos(e) * (z - cz))
  end

  # 0 near, 255 far
  def depth_value(depth)
    ((0.5 - (depth / 60.0)).clamp(0.0, 1.0) * 255).round
  end

  # From the surface towards the eye
  def view_direction
    e = RenderLab::ELEVATION
    [0.0, Math.sin(e), Math.cos(e)]
  end
end
