# Collects gaussian splats as flat numbers and draws them through the engine's positional sprite call,
# which is several times faster than building one Hash per splat every frame.
# Hot loops write into #data directly (STRIDE numbers per splat) and then set #count, which avoids a method
# call per splat.
#
# A batch belongs to one of PostProcess's layers, and the layer decides how its splats blend:
#   :background  alpha blended, behind everything
#   :solid       alpha blended, then alpha tested into opaque pixels with outlines (no translucency)
#   :glow        additive, so splats fade by getting darker; feeds the bloom
class SplatBatch
  STRIDE = 9
  BLENDMODES = { background: 1, solid: 1, glow: 2 }.freeze

  attr_reader :data, :layer
  # shift_x/shift_y move the whole batch on top of the camera offset, e.g. to make one thing tremble on its own
  attr_accessor :count, :shift_x, :shift_y

  # parallax is how much the batch follows the camera: distant things like the sky move less
  def initialize(layer, path: :splat, parallax: 1.0)
    @layer = layer
    @blendmode = BLENDMODES.fetch(layer)
    @path = path.to_s
    @parallax = parallax
    @data = []
    @count = 0
    @shift_x = 0.0
    @shift_y = 0.0
    @offset_x = 0.0
    @offset_y = 0.0
  end

  def clear
    @count = 0
  end

  def primitive_marker
    :sprite
  end

  # PostProcess calls this for every batch it draws
  def follow_camera(camera_x, camera_y)
    @offset_x = (camera_x * @parallax).round + @shift_x
    @offset_y = (camera_y * @parallax).round + @shift_y
  end

  # rubocop:disable-next Metrics/ParameterLists
  def add(x, y, w, h, angle, r, g, b, a)
    d = @data
    i = @count * STRIDE
    d[i] = x
    d[i + 1] = y
    d[i + 2] = w
    d[i + 3] = h
    d[i + 4] = angle
    d[i + 5] = r
    d[i + 6] = g
    d[i + 7] = b
    d[i + 8] = a
    @count += 1
  end

  def draw_override(ffi)
    d = @data
    path = @path
    blendmode = @blendmode
    ox = @offset_x
    oy = @offset_y
    i = 0
    n = @count * STRIDE
    while i < n
      ffi.draw_sprite_6 d[i] + ox, d[i + 1] + oy, d[i + 2], d[i + 3], path, d[i + 4],
                        d[i + 8], d[i + 5], d[i + 6], d[i + 7],
                        nil, nil, nil, nil, false, false, nil, nil, nil, nil, nil, nil,
                        blendmode, 0.5, 0.5, 1
      i += STRIDE
    end
  end
end
