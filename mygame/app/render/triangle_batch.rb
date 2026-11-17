# Solid colored triangles in one of PostProcess's layers, for shapes that sprites cannot fit, like the trapezoids
# of a plane seen in perspective. Like SplatBatch, it collects flat numbers and draws them through the engine's
# positional call; add_quad adds two triangles.
class TriangleBatch
  STRIDE = 10

  attr_reader :layer
  # shift_x/shift_y move the whole batch on top of the camera offset, like SplatBatch's
  attr_accessor :shift_x, :shift_y

  def initialize(layer, parallax: 1.0)
    @layer = layer
    @blendmode = SplatBatch::BLENDMODES.fetch(layer)
    @parallax = parallax
    @data = []
    @count = 0
    @offset_x = 0.0
    @offset_y = 0.0
    @shift_x = 0.0
    @shift_y = 0.0
  end

  def clear
    @count = 0
  end

  def primitive_marker
    :sprite
  end

  def follow_camera(camera_x, camera_y)
    @offset_x = (camera_x * @parallax).round + @shift_x
    @offset_y = (camera_y * @parallax).round + @shift_y
  end

  # rubocop:disable-next Metrics/ParameterLists
  def add(x1, y1, x2, y2, x3, y3, r, g, b, a)
    d = @data
    i = @count * STRIDE
    d[i] = x1
    d[i + 1] = y1
    d[i + 2] = x2
    d[i + 3] = y2
    d[i + 4] = x3
    d[i + 5] = y3
    d[i + 6] = r
    d[i + 7] = g
    d[i + 8] = b
    d[i + 9] = a
    @count += 1
  end

  # Corners in order around the quad
  # rubocop:disable-next Metrics/ParameterLists
  def add_quad(x1, y1, x2, y2, x3, y3, x4, y4, r, g, b, a)
    add(x1, y1, x2, y2, x3, y3, r, g, b, a)
    add(x1, y1, x3, y3, x4, y4, r, g, b, a)
  end

  def draw_override(ffi)
    d = @data
    ox = @offset_x
    oy = @offset_y
    blendmode = @blendmode
    i = 0
    n = @count * STRIDE
    while i < n
      ffi.draw_triangle d[i] + ox, d[i + 1] + oy, d[i + 2] + ox, d[i + 3] + oy, d[i + 4] + ox, d[i + 5] + oy,
                        d[i + 6], d[i + 7], d[i + 8], d[i + 9], 'pixel', nil, nil, nil, nil, nil, nil, blendmode
      i += STRIDE
    end
  end
end
