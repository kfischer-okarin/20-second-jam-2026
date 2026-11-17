# One sprite that takes its place in a layer's drawing order like a SplatBatch: a render target drawn through its
# own shader between two batches (the coffee's surface), or one drawn with a blend mode of its own (shadows).
# sprite is a Hash primitive in scene pixels; it follows the camera like a batch.
class LayerSprite
  # A blend mode that multiplies what is already there and leaves its alpha alone: a shader that outputs
  # (tint * a, a) turns the destination into destination * lerp(1, tint, a). Drawn over nothing, it adds nothing.
  MULTIPLY_BLENDMODE = Numeric.compose_blendmode(BLENDFACTOR_DST_COLOR, BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                                                 BLENDOPERATION_ADD, BLENDFACTOR_ZERO, BLENDFACTOR_ONE,
                                                 BLENDOPERATION_ADD)

  attr_reader :layer
  # shift_x/shift_y move it on top of the camera offset, like SplatBatch's
  attr_accessor :sprite, :visible, :shift_x, :shift_y

  def initialize(layer, sprite: {}, parallax: 1.0)
    @layer = layer
    @sprite = sprite
    @parallax = parallax
    @offset_x = 0
    @offset_y = 0
    @shift_x = 0.0
    @shift_y = 0.0
    @visible = true
  end

  def primitive_marker
    :sprite
  end

  def follow_camera(camera_x, camera_y)
    @offset_x = (camera_x * @parallax).round + @shift_x
    @offset_y = (camera_y * @parallax).round + @shift_y
  end

  def draw_override(ffi)
    return unless @visible

    sprite = @sprite
    x = sprite[:x]
    y = sprite[:y]
    sprite[:x] = x + @offset_x
    sprite[:y] = y + @offset_y
    ffi.draw_sprite_hash sprite
    sprite[:x] = x
    sprite[:y] = y
  end
end
