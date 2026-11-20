# The set pieces in the game's ink look (the INK style), drawn the way ink-studio draws its dioramas (see
# InkSplatScene for the render lab's version):
# - every splat takes one of its material's two tones (InkLook::TWO_TONES), shadow or light. The light is a sun
#   from the left, and each piece is lit as a simpler, rounder shape, its form, so that a rim, an edge or a handle
#   takes the light of what it belongs to instead of flickering between the tones from one splat to the next
# - the splats are crisp ellipses drawn from far to near at twice the screen's resolution, once in their colors
#   and once as depth, and resolve.frag.hlsl turns each 2 by 2 block into one pixel, with ink where a nearer shape
#   ends and around the shapes
# - the saucer, the cup and the moka pot stand still: they are lit once, with hard shadows traced through the
#   scene (RampLighting), and drawn into their targets only when the view changes; the targets keep them. The
#   pitcher moves, so it is lit and drawn every frame, without shadows.
class InkPieces
  SUN_LENGTH = Math.sqrt((0.75 * 0.75) + (0.7 * 0.7) + (0.15 * 0.15))
  # Towards the sun, from the upper left and a little in front
  SUN = [-0.75 / SUN_LENGTH, 0.7 / SUN_LENGTH, 0.15 / SUN_LENGTH].freeze
  AMBIENT = 0.16
  SKY = 0.3
  SUN_STRENGTH = 0.72
  SUPER = 2
  # The crisp ellipse of the :hard texture covers less of its sprite than a soft splat, so splats are drawn this
  # much larger to close the gaps between them, and no thinner than MIN_ASPECT where the eye sees the surface
  # edge on
  COVER = 1.5
  MIN_ASPECT = 0.5
  # Distances from the eye in centimetres that the depth targets hold, as 0 to 255, and the step in depth (as a
  # share of that range) that makes a contour
  NEAR = 5.0
  FAR = 65.0
  CONTOUR = 0.035
  INK = [24, 20, 30].freeze
  STATIC = %i[saucer cup moka_pot].freeze
  # Each piece's parts, how far it reaches from its origin, and the simpler shape it is lit as: an SDF in model
  # space, :up for a flat plate, or nil to be lit as it is
  PIECES = {
    saucer: [:saucer_parts, 7.8, :up],
    cup: [:cup_parts, 9.6, ->(x, y, z) { Sdf.ellipsoid(x, y - 3.0, z, 5.6, 4.0, 5.6) }],
    moka_pot: [:moka_pot_parts, 9.8, ->(x, y, z) { Sdf.ellipsoid(x, y - 4.0, z, 3.0, 6.0, 3.0) }],
    pitcher: [:pitcher_parts, 11.0, lambda { |x, y, z|
      Sdf.ellipsoid(x - Pitcher::BOTTOM[0], y - Pitcher::BOTTOM[1] - 2.0, z, 3.0, 5.0, 3.0)
    }]
  }.freeze
  # Numbers per splat in a piece's data: its position and normal in model space and its size
  STRIDE = 7
  # Numbers per projected splat: its distance from the eye, x, y, width, height, angle, palette index and depth
  # value
  PROJECTED = 8
  # The pieces that stand still are drawn only when the view changes, so they can have smaller splats, closer
  # together by this much (see Models.fine), whose light and shadow have crisper edges. That takes seconds to
  # bake, so the bake is kept in a file (see BakeFiles) and baked again when one of SOURCES changed.
  STATIC_DETAIL = 0.5
  SOURCES = %w[app/render/sdf.rb app/render/sdf_baker.rb app/render/rng.rb app/render/ramp_lighting.rb
               app/latte/models.rb app/latte/cup.rb app/latte/ink_look.rb app/latte/ink_pieces.rb
               app/latte/set_piece_field.rb].freeze

  # What baking leaves for each piece: its splats' data and colors, or for the pitcher the normals of its form
  # (three numbers per splat) and its two tones (two), to light it as it turns
  class Bake
    attr_reader :pieces, :count

    def initialize(pieces)
      @pieces = pieces
      @count = pieces.values.map { |piece| piece[:data].length.idiv(STRIDE) }.inject(0, :+)
    end
  end

  attr_reader :static_sprite, :pitcher_sprite

  # placement: the rotation and position in the world of each of the STATIC pieces, where they are lit
  def initialize(placement)
    @placement = placement
    @static = ModelCache.fetch(:ink_static) {
      Bake.new(BakeFiles.fetch(:ink_static, SOURCES, salt: placement.inspect, integers: [:colors]) {
        InkPieces.bake_static(placement)
      })
    }.pieces
    @pitcher = ModelCache.fetch(:ink_pitcher) { InkPieces.bake_pitcher }.pieces[:pitcher]
    @pitcher_colors = []
    @static_batches = [SplatBatch.new(:solid, path: :hard), SplatBatch.new(:solid, path: :hard)]
    @pitcher_batches = [SplatBatch.new(:solid, path: :hard), SplatBatch.new(:solid, path: :hard)]
    full = { x: 0, y: 0, w: PostProcess::W, h: PostProcess::H, blendmode_enum: 1 }
    @static_sprite = LayerSprite.new(:solid, sprite: full.merge(path: :rt_ink_static))
    @pitcher_sprite = LayerSprite.new(:solid, sprite: full.merge(path: :rt_ink_pitcher))
    @static_key = nil
    upload_palette
  end

  # Every splat of the pieces that stand still, as shadow casters (see Shadows.sample, which takes only some of a
  # model's splats), so that their shadows on the table have smooth edges
  def casters
    @static.to_a.map { |name, piece|
      data = piece[:data]
      xs = []
      ys = []
      zs = []
      i = 0
      while i < data.length
        xs << data[i]
        ys << data[i + 1]
        zs << data[i + 2]
        i += STRIDE
      end
      [name, [xs, ys, zs, Models::BAKES[name][2] * STATIC_DETAIL * 2.6, name != :cup]]
    }.to_h
  end

  # Fills the targets that the two sprites draw. frames has the screen frame ([x, y, scale, elevation] of its
  # origin, see View#point) of each static piece to draw; pitcher is its [frame, rotation], or nil to leave it out.
  # The static pieces' splats are drawn only when their frames changed, but they are resolved every frame: a
  # target keeps what was drawn into it, not what its shader made of that.
  # Must come before PostProcess#render in the tick.
  def render(outputs, focal, frames, pitcher)
    @focal = focal
    key = frames.map { |name, frame| [name, frame.map { |value| value.round(3) }] }
    if key != @static_key
      @static_key = key
      draw_static(outputs, frames)
    end
    resolve(outputs, :static)
    draw_pitcher(outputs, *pitcher) if pitcher
  end

  # --- Baking ----------------------------------------------------------------------------------------------------

  def self.bake_static(placement)
    field = SetPieceField.new(STATIC.map { |name| [Models.send(PIECES[name][0]), *placement[name], PIECES[name][1]] })
    lighting = RampLighting.new(field, sun: SUN, view: SUN, ambient: AMBIENT, sky: SKY, sun_strength: SUN_STRENGTH,
                                       occlusion: 0.0, jitter: 0.0, hard_shadows: true)
    STATIC.map { |name|
      [name, bake_piece(Models.fine(name, STATIC_DETAIL), *placement[name], PIECES[name][2], lighting)]
    }.to_h
  end

  # The light falls on the form, but its shadow is traced from a little off the splat's own surface: off the
  # form's, it could start inside the piece and find it in the way
  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def self.bake_piece(model, rotation, position, form, lighting)
    m0, m1, m2, m3, m4, m5, m6, m7, m8 = rotation
    ox, oy, oz = position
    data = []
    colors = []
    model.count.times do |i|
      px = model.px[i]
      py = model.py[i]
      pz = model.pz[i]
      nx = model.nx[i]
      ny = model.ny[i]
      nz = model.nz[i]
      fx, fy, fz = form_normal(form, px, py, pz, nx, ny, nz)
      x = px + (nx * 0.15)
      y = py + (ny * 0.15)
      z = pz + (nz * 0.15)
      colors << lighting.color(InkLook.two_tone_of(model.cr[i], model.cg[i], model.cb[i]),
                               ox + (m0 * x) + (m1 * y) + (m2 * z), oy + (m3 * x) + (m4 * y) + (m5 * z),
                               oz + (m6 * x) + (m7 * y) + (m8 * z),
                               (m0 * fx) + (m1 * fy) + (m2 * fz), (m3 * fx) + (m4 * fy) + (m5 * fz),
                               (m6 * fx) + (m7 * fy) + (m8 * fz))
      data.push(px, py, pz, nx, ny, nz, model.size[i])
    end
    { data: data, colors: colors }
  end

  def self.bake_pitcher
    model = Models.pitcher
    form = PIECES[:pitcher][2]
    data = []
    forms = []
    tones = []
    model.count.times do |i|
      px = model.px[i]
      py = model.py[i]
      pz = model.pz[i]
      nx = model.nx[i]
      ny = model.ny[i]
      nz = model.nz[i]
      forms.push(*form_normal(form, px, py, pz, nx, ny, nz))
      tones.push(*InkLook.two_tone_of(model.cr[i], model.cg[i], model.cb[i])[:ramp])
      data.push(px, py, pz, nx, ny, nz, model.size[i])
    end
    Bake.new({ pitcher: { data: data, forms: forms, tones: tones } })
  end

  # The normal of the form at a splat, unless the form faces the other way there (inside the cup or the pitcher):
  # then the splat's own
  def self.form_normal(form, x, y, z, nx, ny, nz)
    return [0.0, 1.0, 0.0] if form == :up
    return [nx, ny, nz] unless form

    e = 0.01
    gx = form.call(x + e, y, z) - form.call(x - e, y, z)
    gy = form.call(x, y + e, z) - form.call(x, y - e, z)
    gz = form.call(x, y, z + e) - form.call(x, y, z - e)
    length = Math.sqrt((gx * gx) + (gy * gy) + (gz * gz))
    return [nx, ny, nz] if length < 1e-9 || (gx * nx) + (gy * ny) + (gz * nz) <= 0.0

    [gx / length, gy / length, gz / length]
  end

  private

  # --- Drawing ---------------------------------------------------------------------------------------------------

  def draw_static(outputs, frames)
    projected = []
    frames.each do |name, frame|
      piece = @static[name]
      matrix = Rot3.mul(Rot3.rot_x(frame[3]), @placement[name][0])
      project(projected, piece[:data], piece[:colors], matrix, frame)
    end
    draw(outputs, :static, @static_batches, projected)
  end

  def draw_pitcher(outputs, frame, rotation)
    light_pitcher(rotation)
    projected = []
    project(projected, @pitcher[:data], @pitcher_colors, Rot3.mul(Rot3.rot_x(frame[3]), rotation), frame)
    draw(outputs, :pitcher, @pitcher_batches, projected)
    resolve(outputs, :pitcher)
  end

  # Picks each of the pitcher's splats' tone by the light on its form, as RampLighting does without shadows: the
  # sun and up are turned into the pitcher's model space (by the transpose of its rotation)
  # rubocop:disable-next Metrics/AbcSize
  def light_pitcher(rotation)
    m0, m1, m2, m3, m4, m5, m6, m7, m8 = rotation
    lx, ly, lz = SUN
    sx = (m0 * lx) + (m3 * ly) + (m6 * lz)
    sy = (m1 * lx) + (m4 * ly) + (m7 * lz)
    sz = (m2 * lx) + (m5 * ly) + (m8 * lz)
    forms = @pitcher[:forms]
    tones = @pitcher[:tones]
    colors = @pitcher_colors
    n = tones.length.idiv(2)
    i = 0
    while i < n
      fx = forms[i * 3]
      fy = forms[(i * 3) + 1]
      fz = forms[(i * 3) + 2]
      sun = (fx * sx) + (fy * sy) + (fz * sz)
      sun = 0.0 if sun < 0.0
      light = AMBIENT + (SKY * (0.5 + (0.5 * ((fx * m3) + (fy * m4) + (fz * m5))))) + (SUN_STRENGTH * sun)
      colors[i] = tones[(i * 2) + (light >= 0.5 ? 1 : 0)]
      i += 1
    end
  end

  # Appends each splat that faces the eye to projected (PROJECTED numbers each), at twice the resolution. Hot loop
  # over a piece's splats.
  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def project(projected, data, colors, matrix, frame)
    m0, m1, m2, m3, m4, m5, m6, m7, m8 = matrix
    tx, ty, scale, = frame
    forward = @focal / scale
    grow = scale * SUPER * COVER
    depth_scale = 255.0 / (FAR - NEAR)
    i = 0
    j = projected.length
    k = 0
    n = data.length
    while i < n
      nx = data[i + 3]
      ny = data[i + 4]
      nz = data[i + 5]
      view_z = (m6 * nx) + (m7 * ny) + (m8 * nz)
      if view_z > -0.12
        px = data[i]
        py = data[i + 1]
        pz = data[i + 2]
        distance = forward - ((m6 * px) + (m7 * py) + (m8 * pz))
        w = data[i + 6] * grow
        aspect = view_z.abs.clamp(MIN_ASPECT, 1.0)
        projected[j] = distance
        projected[j + 1] = (tx + (((m0 * px) + (m1 * py) + (m2 * pz)) * scale)) * SUPER
        projected[j + 2] = (ty + (((m3 * px) + (m4 * py) + (m5 * pz)) * scale)) * SUPER
        projected[j + 3] = w
        projected[j + 4] = w * aspect
        projected[j + 5] = (Math.atan2((m3 * nx) + (m4 * ny) + (m5 * nz), (m0 * nx) + (m1 * ny) + (m2 * nz)) *
                            SplatRenderer::RAD_TO_DEG) - 90.0
        projected[j + 6] = colors[k]
        projected[j + 7] = ((distance - NEAR) * depth_scale).clamp(0.0, 255.0).round
        j += PROJECTED
      end
      i += STRIDE
      k += 1
    end
  end

  # The splats from far to near into the color and depth targets
  def draw(outputs, name, batches, projected)
    color_batch, depth_batch = batches
    color_batch.clear
    depth_batch.clear
    palette = InkLook::PALETTE
    far_to_near(projected).each do |j|
      x = projected[j + 1]
      y = projected[j + 2]
      w = projected[j + 3]
      h = projected[j + 4]
      angle = projected[j + 5]
      r, g, b = palette[projected[j + 6]]
      value = projected[j + 7]
      color_batch.add(x, y, w, h, angle, r, g, b, 255)
      depth_batch.add(x, y, w, h, angle, value, value, value, 255)
    end
    fill_target(outputs, :"rt_ink_#{name}_color", color_batch)
    fill_target(outputs, :"rt_ink_#{name}_depth", depth_batch)
  end

  # Where each projected splat starts, from far to near: sorted into buckets of distance (about four splats to a
  # bucket), whose order inside is fine enough to draw by, which takes much less time than sorting them
  def far_to_near(projected)
    n = projected.length
    return [] if n.zero?

    near = far = projected[0]
    j = 0
    while j < n
      distance = projected[j]
      near = distance if distance < near
      far = distance if distance > far
      j += PROJECTED
    end
    count = (n.idiv(PROJECTED * 4) + 1).clamp(16, 4096)
    scale = (count - 1) / [far - near, 1e-6].max
    buckets = Array.new(count) { [] }
    j = 0
    while j < n
      buckets[((far - projected[j]) * scale).to_i] << j
      j += PROJECTED
    end
    buckets.flatten
  end

  # Cleared to transparent black: what is drawn into it is stored premultiplied, and the resolve divides by alpha
  def fill_target(outputs, name, batch)
    target = outputs[name]
    target.set w: PostProcess::W * SUPER, h: PostProcess::H * SUPER, background_color: [0, 0, 0, 0]
    target.primitives << batch
  end

  # The color and depth targets through resolve.frag.hlsl into the one the sprite draws
  def resolve(outputs, name)
    w = PostProcess::W * SUPER
    h = PostProcess::H * SUPER
    target = outputs[:"rt_ink_#{name}"]
    target.set w: w, h: h, background_color: [0, 0, 0, 0]
    target.primitives << { x: 0, y: 0, w: w, h: h, path: :"rt_ink_#{name}_color", blendmode_enum: 0 }
    values = [InkLook::PALETTE.length, CONTOUR, 1.0, 1.0, *INK.map { |c| c / 255.0 }, 0.0]
    target.shader = { path: 'shaders/resolve.frag.hlsl', textures: [:"rt_ink_#{name}_depth", :ink_palette],
                      uniforms: values.map { |value| { type: :float, value: value.to_f } } }
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
end
