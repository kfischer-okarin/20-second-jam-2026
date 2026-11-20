# Shadows cast by the objects on the terrace. A sample of every caster's splats is projected along the light
# onto the first thing below it: the coffee, the saucer or the table. Each hit becomes a white splat in a
# coverage target, rt_shadow_low (table and saucer) or rt_shadow_high (coffee), and the shadow shader turns that
# coverage into an even shadow that multiplies whatever was drawn before it in a layer (see LayerSprite).
# The table's shadows go into the background layer after the table, the saucer's into the solid layer after the
# saucer and before the cup, which then hides the shadow behind it; the coffee's after the coffee.
class Shadows
  SAMPLES = 700
  TINT = [0.62, 0.52, 0.56].freeze

  attr_reader :table_sprite, :saucer_sprite, :coffee_sprite
  # hard gives shadows a hard edge instead of a soft one
  attr_accessor :tint, :strength, :hard

  # A caster: about samples of a model's splats in model space, how big a shadow splat each one makes, and
  # whether it shades the coffee (the cup does not: its art is what the player looks at)
  def self.sample(model, spacing, coffee: true, samples: SAMPLES)
    stride = [model.count.idiv(samples), 1].max
    xs = []
    ys = []
    zs = []
    i = 0
    while i < model.count
      xs << model.px[i]
      ys << model.py[i]
      zs << model.pz[i]
      i += stride
    end
    [xs, ys, zs, spacing * Math.sqrt(stride) * 2.6, coffee]
  end

  def initialize
    @static = SplatBatch.new(:background)
    @moving = SplatBatch.new(:background)
    @static_high = SplatBatch.new(:background)
    @moving_high = SplatBatch.new(:background)
    @tint = TINT
    @strength = 0.6
    @hard = false
    @static_changed = true
    full = { x: 0, y: 0, w: PostProcess::W, h: PostProcess::H, blendmode: LayerSprite::MULTIPLY_BLENDMODE }
    @table_sprite = LayerSprite.new(:background, sprite: full.merge(path: :rt_shadow_low))
    @saucer_sprite = LayerSprite.new(:solid, sprite: full.merge(path: :rt_shadow_low))
    @coffee_sprite = LayerSprite.new(:solid, sprite: full.merge(path: :rt_shadow_high))
  end

  # Casters that stay put are cast again only when the light changed, and their coverage is kept in targets of its
  # own until then; the pitcher is cast every frame
  def clear_static
    @static.clear
    @static_high.clear
    @static_changed = true
  end

  def clear_moving
    @moving.clear
    @moving_high.clear
  end

  # scene describes the receivers and the light: see Terrace#shadow_scene. table_only leaves the saucer and the
  # coffee out, for shadows that are already part of how they are drawn.
  def cast_static(caster, matrix, position, scene, table_only: false)
    cast(@static, @static_high, caster, matrix, position, scene, table_only)
  end

  def cast_moving(caster, matrix, position, scene)
    cast(@moving, @moving_high, caster, matrix, position, scene, false)
  end

  # Fills the coverage targets. Must come before the layers that draw them in the tick.
  def render_targets(outputs)
    if @static_changed
      coverage(outputs, :rt_shadow_static_low, @static)
      coverage(outputs, :rt_shadow_static_high, @static_high)
      @static_changed = false
    end
    uniforms = [*@tint, @strength, @hard ? 1.0 : 0.0, 0.0, 0.0, 0.0].map { |value| { type: :float, value: value.to_f } }
    [[:rt_shadow_low, :rt_shadow_static_low, @moving],
     [:rt_shadow_high, :rt_shadow_static_high, @moving_high]].each do |name, static, moving|
      target = coverage(outputs, name, moving)
      target.primitives << { x: 0, y: 0, w: PostProcess::W, h: PostProcess::H, path: static, blendmode_enum: 1 }
      target.shader = { path: 'shaders/shadow.frag.hlsl', uniforms: uniforms }
    end
  end

  private

  def coverage(outputs, name, batch)
    target = outputs[name]
    target.set w: PostProcess::W, h: PostProcess::H, background_color: [0, 0, 0, 0]
    target.primitives << batch
    target
  end

  # Hot loop over the caster's sample points. A point at height y lands run_x * y to the side and run_z * y
  # towards the eye of where it is.
  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def cast(low, high, caster, matrix, position, scene, table_only)
    xs, ys, zs, size, shades_coffee = caster
    m0, m1, m2, m3, m4, m5, m6, m7, m8 = matrix
    ox, oy, oz = position
    run_x = scene[:run_x]
    run = scene[:run_z]
    stretch = scene[:stretch]
    level = shades_coffee && !table_only ? scene[:level] : 1000.0
    coffee2 = scene[:coffee_radius]**2
    saucer_y = table_only ? 1000.0 : scene[:saucer_y]
    saucer2 = scene[:saucer_radius]**2
    cup_x, cup_y, cup_scale, cup_cos, cup_sin = scene[:cup]
    height, distance, cos_p, sin_p, focal = scene[:camera]
    center_x = View::CENTER_X
    center_y = View::CENTER_Y
    cup_w = size * cup_scale
    cup_h = cup_w * cup_sin * stretch
    i = 0
    n = xs.length
    while i < n
      x = xs[i]
      y = ys[i]
      z = zs[i]
      wx = ox + (m0 * x) + (m1 * y) + (m2 * z)
      wy = oy + (m3 * x) + (m4 * y) + (m5 * z)
      wz = oz + (m6 * x) + (m7 * y) + (m8 * z)
      i += 1
      if wy > level
        hx = wx + ((wy - level) * run_x)
        hz = wz + ((wy - level) * run)
        if (hx * hx) + (hz * hz) < coffee2
          high.add(cup_x + (hx * cup_scale), cup_y + (((level * cup_cos) - (hz * cup_sin)) * cup_scale),
                   cup_w, cup_h, 0.0, 255, 255, 255, 255)
          next
        end
      end
      if wy > saucer_y
        hx = wx + ((wy - saucer_y) * run_x)
        hz = wz + ((wy - saucer_y) * run)
        if (hx * hx) + (hz * hz) < saucer2
          low.add(cup_x + (hx * cup_scale), cup_y + (((saucer_y * cup_cos) - (hz * cup_sin)) * cup_scale),
                  cup_w, cup_h, 0.0, 255, 255, 255, 255)
          next
        end
      end
      hx = wx + (wy * run_x)
      hz = wz + (wy * run)
      ahead = distance - hz
      forward = (ahead * cos_p) + (height * sin_p)
      next if forward < 1.0

      scale = focal / forward
      up = (ahead * sin_p) - (height * cos_p)
      w = size * scale
      low.add(center_x + (hx * scale), center_y + (up * scale), w, w * height / forward * stretch, 0.0,
              255, 255, 255, 255)
    end
  end
end
