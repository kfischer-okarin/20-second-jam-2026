# Owns the render target chain. Every layer is drawn at the low resolution and the post shader turns the
# layers into the final pixel image, which is scaled up with nearest neighbour filtering.
# (Render target names carry an rt_ prefix because DragonRuby reserves some plain names such as :solid.)
#
#   rt_bg ──────────────────────────────────────────────────────────────────────┐
#   rt_solid ──┬─────────────────────────────────────────────────────────────────┼─> rt_final (post) ─> screen
#   rt_glow ───┴─> rt_bright (bright pass, half size) ─> rt_blur1 ─> rt_blur2 ─> rt_blur3 ─┤
#   rt_ui ───────────────────────────────────────────────────────────────────────┘
class PostProcess
  W = 320
  H = 180
  SCALE = 4
  MAX_WAVES = 4
  DEBUG_VIEWS = %i[rt_final rt_bg rt_solid rt_glow rt_bright rt_blur1 rt_blur2 rt_blur3 rt_ui].freeze
  # The most colors a palette can have (the width of the texture the post shader reads it from)
  PALETTE_SLOTS = 64
  ENDESGA32 = [
    [190, 74, 47], [215, 118, 67], [234, 212, 170], [228, 166, 114], [184, 111, 80], [115, 62, 57], [62, 39, 49],
    [162, 38, 51], [228, 59, 68], [247, 118, 34], [254, 174, 52], [254, 231, 97], [99, 199, 77], [62, 137, 72],
    [38, 92, 66], [25, 60, 62], [18, 78, 137], [0, 153, 219], [44, 232, 245], [255, 255, 255], [192, 203, 220],
    [139, 155, 180], [90, 105, 136], [58, 68, 102], [38, 43, 68], [24, 20, 37], [255, 0, 68], [104, 56, 108],
    [181, 80, 136], [246, 117, 122], [232, 183, 150], [194, 133, 105]
  ].freeze

  # background_color shows wherever nothing is drawn; shadow_tint (0..1) adds shadow_tint_color to dark tones.
  # Light brighter than bright_threshold blooms: in the glow layer, and in the solid layer too with bloom_solid.
  # exposure multiplies the scene before flash and grading. veil (0..1) closes veil_color in from the edges of
  # the screen, with a soft edge veil_softness wide. palette is the colors every pixel ends up as (all colors
  # stay when it is empty).
  # smooth (pixels, 0 for none) evens out the solid layer before that: each pixel averages its neighbors within
  # smooth that are close to its own color, closer the higher smooth_sharpness.
  attr_accessor :background_color, :bloom, :aberration, :dither, :flash, :flash_color, :shadow_tint,
                :shadow_tint_color, :vignette, :saturation, :outline, :bright_threshold, :bloom_solid, :exposure, :veil,
                :veil_softness, :veil_color, :palette, :smooth, :smooth_sharpness

  # The render target shown on screen. It belongs to the class so that a chosen view survives restarts of the
  # game (saving code, scripts/game reset).
  class << self
    attr_accessor :debug_view
  end
  @debug_view ||= :rt_final

  def initialize
    @background_color = [24, 20, 37]
    @bloom = 0.9
    @aberration = 0.0
    @dither = 1.0
    @flash = 0.0
    @flash_color = [1.0, 1.0, 1.0]
    @shadow_tint = 0.0
    @shadow_tint_color = [0.0, 0.0, 0.0]
    @vignette = 0.35
    @saturation = 1.1
    @outline = 1.0
    @bright_threshold = 0.76
    @bloom_solid = true
    @exposure = 1.0
    @veil = 0.0
    @veil_softness = 0.3
    @veil_color = [1.0, 1.0, 1.0]
    @palette = ENDESGA32
    @smooth = 0
    @smooth_sharpness = 40.0
  end

  def debug_view
    PostProcess.debug_view
  end

  def debug_view=(view)
    PostProcess.debug_view = view
  end

  # batches are SplatBatches (or anything else with a layer and follow_camera, like a LayerSprite) in drawing
  # order; each goes to the render target of its layer and follows the camera. hud is primitives in scene pixels
  # that stay put. waves are [x, y, radius, strength] in scene pixels with y pointing up.
  def render(outputs, batches:, camera:, hud:, waves:, time:)
    batches.each do |batch|
      batch.follow_camera(camera.offset_x, camera.offset_y)
    end
    layer(outputs, :rt_bg, [*@background_color, 255], batches.select { |batch| batch.layer == :background })
    layer(outputs, :rt_solid, [0, 0, 0, 0], batches.select { |batch| batch.layer == :solid })
    layer(outputs, :rt_glow, [0, 0, 0, 0], batches.select { |batch| batch.layer == :glow })
    layer(outputs, :rt_ui, [0, 0, 0, 0], hud)
    bright_pass(outputs)
    downsample(outputs, :rt_blur1, :rt_bright, 80, 45)
    downsample(outputs, :rt_blur2, :rt_blur1, 40, 23)
    downsample(outputs, :rt_blur3, :rt_blur2, 20, 12)
    final_pass(outputs, waves, time)
    outputs.primitives << { x: 0, y: 0, w: W * SCALE, h: H * SCALE, path: debug_view, scale_quality_enum: 0 }
  end

  def cycle_debug_view
    self.debug_view = DEBUG_VIEWS[(DEBUG_VIEWS.index(debug_view) + 1) % DEBUG_VIEWS.length]
  end

  private

  def layer(outputs, name, background_color, primitives)
    target = outputs[name]
    target.set w: W, h: H, background_color: background_color
    target.primitives << primitives
  end

  def bright_pass(outputs)
    w = W.idiv(2)
    h = H.idiv(2)
    target = outputs[:rt_bright]
    target.set w: w, h: h, background_color: [0, 0, 0, 255]
    # The glow layer goes in as a texture: its alpha is 0, so drawing it into the target would add nothing
    target.shader = {
      path: 'shaders/bright_pass.frag.hlsl',
      textures: [:rt_glow],
      uniforms: [{ type: :float, value: @bright_threshold }, { type: :float, value: 1.4 },
                 { type: :float, value: @bloom_solid ? 1.0 : 0.0 }]
    }
    target.primitives << { x: 0, y: 0, w: w, h: h, path: :rt_solid, blendmode_enum: 0, scale_quality_enum: 1 }
  end

  def downsample(outputs, name, source, w, h)
    target = outputs[name]
    target.set w: w, h: h, background_color: [0, 0, 0, 255]
    target.primitives << { x: 0, y: 0, w: w, h: h, path: source, blendmode_enum: 0, scale_quality_enum: 1 }
  end

  def final_pass(outputs, waves, time)
    upload_palette
    target = outputs[:rt_final]
    target.set w: W, h: H, background_color: [0, 0, 0, 0]
    target.shader = {
      path: 'shaders/post.frag.hlsl',
      textures: %i[rt_bg rt_glow rt_blur1 rt_blur2 rt_blur3 rt_ui post_palette],
      uniforms: uniforms(waves, time)
    }
    target.primitives << { x: 0, y: 0, w: W, h: H, path: :rt_solid, blendmode_enum: 0 }
  end

  # The palette goes to the shader as a row of pixels, written again only when it changed
  def upload_palette
    return if @uploaded_palette.equal?(@palette)

    pixels = Array.new(PALETTE_SLOTS, 0xFF00_0000)
    @palette.first(PALETTE_SLOTS).each_with_index do |(r, g, b), i|
      pixels[i] = 0xFF00_0000 | (b << 16) | (g << 8) | r
    end
    pixel_array = $gtk.args.pixel_array(:post_palette)
    pixel_array.w = PALETTE_SLOTS
    pixel_array.h = 1
    pixel_array.pixels = pixels
    @uploaded_palette = @palette
  end

  def uniforms(waves, time)
    values = [time, @bloom, @aberration, @dither]
    values.concat(@flash_color)
    values << @flash
    values.push(@shadow_tint, @vignette, @saturation, @outline)
    values.concat(@shadow_tint_color)
    values << @smooth
    strongest = waves.sort_by { |wave| -wave[3].abs }.first(MAX_WAVES)
    MAX_WAVES.times do |i|
      x, y, radius, strength = strongest[i] || [0.0, 0.0, 0.0, 0.0]
      values.push(x, H - y, radius, strength)
    end
    values.push(@veil, @veil_softness, @exposure, [@palette.length, PALETTE_SLOTS].min)
    values.concat(@veil_color)
    values << @smooth_sharpness
    values.map { |value| { type: :float, value: value.to_f } }
  end
end
