# The man, seen only in the ending: his hand taking the cup (E1) and his face and chest (E2). Model space is in
# centimetres like the terrace (x right, y up, z towards the eye).
module EndingModels
  SKIN = [214, 150, 108].freeze
  SKIN_SHADOW = [176, 108, 80].freeze
  LINE = [112, 58, 52].freeze
  ROSY = [226, 138, 112].freeze
  SILVER = [214, 216, 226].freeze
  BEARD = [244, 240, 232].freeze
  SHIRT = [246, 242, 234].freeze
  DENIM = [40, 50, 86].freeze
  DENIM_LIGHT = [60, 72, 112].freeze
  METAL = [196, 202, 214].freeze
  WATCH = [36, 34, 44].freeze

  # How each model is baked: the method with its parts, its bounds, splat spacing, size and seed, and which
  # splats it keeps
  BAKES = {
    # His right forearm and hand reaching along +x with the back of the hand up; the fingertips curl down at
    # about (2.4, -1.6, 0), where they hook around the cup's handle
    hand: [:hand_parts, [-24.5, -3.0, -3.6, 3.4, 4.6, 3.6], 0.32, 21],
    # His head with silver hair, beard and closed, smiling eyes, centered on the origin and facing the eye
    head: [:head_parts, [-9.0, -13.5, -10.8, 9.0, 12.4, 11.2], 0.4, 22],
    # Neck, shoulders in a white t-shirt, and the bib of his overalls, in the head's coordinates
    body: [:body_parts, [-20.0, -36.0, -11.0, 20.0, -9.0, 9.4], 0.6, 23],
    # A loose fist with the thumb on top, holding something by a handle at the origin, the forearm going down
    # and to the right
    fist: [:fist_parts, [-2.4, -16.0, -3.4, 12.0, 3.4, 3.6], 0.34, 24]
  }.freeze

  extend self

  def hand = model(:hand)
  def head = model(:head)
  def body = model(:body)
  def fist = model(:fist)

  # Queues every model for baking in the background (see ModelCache)
  def prepare
    BAKES.each_key do |name|
      ModelCache.prepare(name) { bake(name) }
    end
  end

  def model(name)
    ModelCache.fetch(name) { bake(name) }
  end

  def bake(name)
    parts, bounds, spacing, seed = BAKES.fetch(name)
    keep = name == :body ? ->(_x, _y, z) { z > -3.0 } : nil
    SdfBaker.bake(send(parts), bounds: bounds, spacing: spacing, size: spacing * 3.0, seed: seed, keep: keep)
  end

  def hand_parts
    [
      { sdf: ->(x, y, z) { Sdf.cone_between(x, y, z, [-4.6, 0.4, 0.0], [-22.0, 1.6, 0.0], 1.75, 2.3) },
        color: SKIN },
      { sdf: ->(x, y, z) { Sdf.ellipsoid(x + 2.0, y - 0.3, z, 2.9, 1.15, 2.1) }, color: SKIN, blend: 0.9 },
      *finger_parts,
      { sdf: ->(x, y, z) { Sdf.capsule(x, y, z, [-1.8, 0.0, 1.9], [0.0, 0.5, 2.5], 0.52) }, color: SKIN, blend: 0.4 },
      { sdf: ->(x, y, z) { Sdf.capsule(x, y, z, [0.0, 0.5, 2.5], [1.2, 0.8, 1.9], 0.45) }, color: SKIN, blend: 0.2 },
      { sdf: ->(x, y, z) { Sdf.cylinder(y - 0.5, x + 6.6, z, 1.98, 0.6, 0.25) }, color: WATCH, gloss: 0.2,
        blend: 0.1 },
      { sdf: ->(x, y, z) { Sdf.cylinder(x + 6.6, y - 2.4, z, 1.0, 0.22, 0.1) }, color: WATCH, gloss: 0.4 },
      { sdf: ->(x, y, z) { Sdf.torus(x + 6.6, y - 2.6, z, 1.0, 0.16) }, color: METAL, gloss: 0.8 },
      { sdf: ->(x, y, z) { Sdf.cylinder(x + 6.6, y - 2.62, z, 0.7, 0.1) }, color: [150, 154, 166], paint: true }
    ]
  end

  def finger_parts
    [-1.35, -0.45, 0.45, 1.3].each_with_index.flat_map do |z, i|
      reach = i == 3 ? 0.75 : 1.0
      knuckle = [0.4, 0.3, z]
      middle = [0.4 + (1.5 * reach), -0.25, z * 1.04]
      tip = [0.4 + (2.0 * reach), -1.5 * reach, z * 1.06]
      [
        { sdf: ->(x, y, zz) { Sdf.capsule(x, y, zz, knuckle, middle, 0.44) }, color: SKIN, blend: 0.35 },
        { sdf: ->(x, y, zz) { Sdf.capsule(x, y, zz, middle, tip, 0.39) }, color: SKIN, blend: 0.15 }
      ]
    end
  end

  def head_parts
    [
      { sdf: ->(x, y, z) { Sdf.ellipsoid(x, y, z, 7.0, 9.6, 8.2) }, color: SKIN },
      { sdf: ->(x, y, z) { Sdf.ellipsoid(x, y + 4.4, z - 1.6, 6.1, 6.0, 6.8) }, color: SKIN, blend: 1.4 },
      { sdf: ->(x, y, z) { Sdf.ellipsoid(x.abs - 6.9, y, z + 0.4, 1.2, 2.7, 1.8) }, color: SKIN, blend: 0.6 },
      { sdf: ->(x, y, z) { Sdf.ellipsoid(x, y - 3.2, z - 6.1, 5.4, 1.3, 2.2) }, color: SKIN, blend: 1.0 },
      { sdf: ->(x, y, z) { Sdf.cone_between(x, y, z, [0.0, 2.0, 7.7], [0.0, -1.5, 9.5], 0.85, 1.25) }, color: SKIN,
        blend: 0.6 },
      { sdf: ->(x, y, z) { Sdf.ellipsoid(x, y + 1.9, z - 9.0, 1.65, 1.1, 1.2) }, color: SKIN, blend: 0.5 },
      { sdf: ->(x, y, z) { Sdf.ellipsoid(x.abs - 3.6, y + 1.0, z - 6.0, 2.5, 1.9, 2.0) }, color: SKIN, blend: 1.2 },
      { sdf: ->(x, y, z) { hair(x, y, z) }, color: SILVER, gloss: 0.15, blend: 0.3 },
      { sdf: ->(x, y, z) { Sdf.ellipsoid(x.abs - 2.8, y - 3.6 + (x.abs * 0.06), z - 7.25, 1.95, 0.55, 0.85) },
        color: SILVER, blend: 0.25 },
      { sdf: ->(x, y, z) { beard(x, y, z) }, color: BEARD, blend: 0.45 },
      { sdf: ->(x, y, z) { Sdf.ellipsoid(x, y + 3.0, z - 8.55, 3.2, 0.95, 1.2) }, color: BEARD, blend: 0.5 },
      { sdf: ->(x, y, z) { Sdf.ellipsoid(x.abs - 2.5, y + 3.65, z - 8.0, 1.25, 1.05, 1.05) }, color: BEARD,
        blend: 0.45 },
      *face_paint
    ]
  end

  # Tousled silver hair swept back from the forehead: ridges run from front to back, with waves across them
  def hair(x, y, z)
    tousle = (Math.sin((x * 1.7) + (Math.sin(z * 0.45) * 1.3)) * 0.32) + (Math.sin((y * 1.3) + (x * 0.6)) * 0.18)
    shell = Sdf.ellipsoid(x, y - 2.0, z + 1.2, 7.7, 9.5, 9.0) - 0.3 - tousle
    line = 6.0 + ([z - 4.0, 0.0].min * 0.95) - ([x.abs - 4.8, 0.0].max * 1.3)
    # rubocop:disable-next Style/MinMaxComparison
    shell > line - y ? shell : line - y
  end

  # A neatly trimmed beard around the jaw, below the cheeks
  def beard(x, y, z)
    tufts = Math.sin((x * 2.3) + (y * 1.1)) * Math.sin((y * 2.1) - (z * 0.9)) * 0.18
    shell = Sdf.ellipsoid(x, y + 5.4, z - 2.2, 6.65, 6.2, 7.2) - tufts
    cut = y + 2.7 + (x.abs * 0.12)
    # rubocop:disable-next Style/MinMaxComparison
    shell > cut ? shell : cut
  end

  # Lines drawn onto the face: closed eyelids, smile lines and wrinkles, the smile, rosy cheeks
  def face_paint
    [
      { sdf: ->(x, y, z) { [arc(x.abs - 2.75, y - 2.55, 1.55, 0.26), y - 1.55, 4.0 - z].max }, color: LINE,
        paint: true },
      { sdf: ->(x, y, z) { [arc(x.abs - 4.7, y - 2.9, 1.6, 0.17), x.abs - 6.0, 4.4 - x.abs, 3.0 - z].max },
        color: SKIN_SHADOW, paint: true },
      { sdf: ->(x, y, z) { [arc(x, y + 7.0, 12.0, 0.17), x.abs - 3.4, 5.0 - z].max }, color: SKIN_SHADOW,
        paint: true },
      { sdf: ->(x, y, z) { [arc(x, y + 7.0, 13.1, 0.17), x.abs - 3.0, 5.0 - z].max }, color: SKIN_SHADOW,
        paint: true },
      { sdf: ->(x, y, z) { [arc(x, y + 1.3, 3.05, 0.26), y + 3.75, x.abs - 2.2, 6.0 - z].max }, color: LINE,
        paint: true },
      { sdf: ->(x, y, z) { [arc(x, y - 0.6, 4.3, 0.17), y + 0.6, -2.4 - y, 2.4 - x.abs, 5.0 - z].max },
        color: SKIN_SHADOW, paint: true },
      { sdf: ->(x, y, z) { Sdf.ellipsoid(x.abs - 3.9, y + 0.7, z - 7.0, 1.7, 1.2, 3.0) }, color: ROSY, paint: true }
    ]
  end

  # Distance to a ring of the given radius around (0, 0) in the xy plane, as a band thickness wide
  def arc(x, y, radius, thickness)
    (Math.sqrt((x * x) + (y * y)) - radius).abs - thickness
  end

  def body_parts
    [
      { sdf: ->(x, y, z) { Sdf.cylinder(x, y + 12.5, z + 0.8, 4.5, 3.2) }, color: SKIN },
      { sdf: ->(x, y, z) { Sdf.ellipsoid(x, y + 24.5, z + 1.5, 18.0, 9.8, 8.6) }, color: SHIRT, blend: 2.0 },
      { sdf: ->(x, y, z) { Sdf.torus(x, y + 15.0, z + 0.4, 4.9, 0.65) }, color: SHIRT, blend: 0.6 },
      { sdf: ->(x, y, z) { Sdf.round_box(x, y + 28.5, z - 6.0, 7.4, 6.6, 1.2, 0.7) }, color: DENIM, blend: 0.8 },
      { sdf: ->(x, y, z) { Sdf.capsule(x.abs, y, z, [5.9, -22.4, 6.6], [8.6, -16.0, 2.2], 1.2) }, color: DENIM,
        blend: 0.4 },
      { sdf: ->(x, y, z) { Sdf.capsule(x.abs, y, z, [8.6, -16.0, 2.2], [9.2, -15.4, -4.0], 1.2) }, color: DENIM,
        blend: 0.3 },
      { sdf: ->(x, y, z) { Sdf.round_box(x.abs - 5.9, y + 22.0, z - 7.45, 1.15, 0.85, 0.4, 0.3) }, color: METAL,
        gloss: 0.8, blend: 0.1 },
      { sdf: ->(x, y, z) { Sdf.round_box(x - 2.3, y + 26.4, z - 7.0, 3.0, 2.8, 2.0, 0.3) }, color: DENIM_LIGHT,
        paint: true }
    ]
  end

  def fist_parts
    [
      { sdf: ->(x, y, z) { Sdf.cone_between(x, y, z, [4.4, -1.6, 0.0], [12.0, -16.0, 0.0], 1.8, 2.3) }, color: SKIN },
      { sdf: ->(x, y, z) { Sdf.ellipsoid(x - 2.6, y + 0.2, z, 2.3, 2.6, 2.0) }, color: SKIN, blend: 1.0 },
      *[-1.5, -0.5, 0.5, 1.5].map { |y|
        { sdf: ->(x, yy, z) { Sdf.capsule(x, yy, z, [1.0, y, -1.4], [0.2, y * 0.95, 0.9], 0.48) }, color: SKIN,
          blend: 0.3 }
      },
      { sdf: ->(x, y, z) { Sdf.capsule(x, y, z, [2.6, 1.8, 1.4], [0.3, 2.3, 1.2], 0.55) }, color: SKIN, blend: 0.4 },
      { sdf: ->(x, y, z) { Sdf.cone_between(x, y, z, [6.6, -5.8, 0.0], [7.2, -6.9, 0.0], 2.05, 2.1) }, color: WATCH,
        gloss: 0.2, blend: 0.1 }
    ]
  end
end
