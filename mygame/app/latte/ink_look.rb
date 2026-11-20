# A palette made of ramps, one for every material of the set pieces, for lighting baked into palette colors (see
# RampLighting): each ramp runs from a shadow that leans cool to a light that leans warm, so shade has color
# instead of only getting darker.
module InkLook
  PALETTE = [
    [24, 20, 30],
    # table: a purple brown in shadow to a sunlit pale wood
    [82, 56, 66], [128, 88, 78], [176, 128, 98], [214, 168, 124], [238, 206, 160],
    # glaze
    [28, 30, 64], [44, 60, 116], [72, 102, 164], [122, 160, 214],
    # porcelain
    [120, 122, 158], [184, 184, 206], [234, 228, 218], [255, 250, 238],
    # steel
    [60, 66, 92], [106, 118, 146], [166, 178, 200], [224, 232, 242],
    # aluminium
    [78, 78, 96], [128, 130, 146], [182, 184, 194], [232, 230, 230],
    # bakelite
    [34, 26, 32], [68, 54, 60],
    # coffee
    [52, 28, 26], [94, 54, 40], [146, 92, 58], [192, 136, 90],
    # milk foam
    [226, 212, 196], [250, 244, 232],
    # glints
    [255, 255, 255], [255, 230, 186]
  ].freeze

  GLINT = 30
  MATERIALS = {
    table: { ramp: [1, 2, 3, 4, 5] },
    glaze: { ramp: [6, 7, 8, 9], glint: GLINT },
    porcelain: { ramp: [10, 11, 12, 13], glint: GLINT },
    steel: { ramp: [14, 15, 16, 17], glint: GLINT, glint_at: 0.93 },
    aluminium: { ramp: [18, 19, 20, 21], glint: GLINT, glint_at: 0.94 },
    bakelite: { ramp: [22, 23], glint: 21 },
    milk: { ramp: [28, 29, 29] }
  }.freeze

  # The game's ink look (see InkPieces) has only two tones of each, for shadow and light
  TWO_TONES = {
    glaze: { ramp: [7, 8] }, porcelain: { ramp: [11, 12] }, steel: { ramp: [15, 16] },
    aluminium: { ramp: [19, 20] }, bakelite: { ramp: [22, 23] }, milk: { ramp: [28, 29] }
  }.freeze
  # The table's two tones
  TABLE = 4
  TABLE_SHADOW = 3

  # The material a baked splat belongs to, from the albedo the baker gave it
  BY_ALBEDO = {
    glaze: Models::GLAZE, porcelain: Models::PORCELAIN, steel: Models::STEEL, aluminium: Models::ALUMINIUM,
    bakelite: Models::BAKELITE, milk: Models::MILK
  }.freeze

  def self.material_of(r, g, b) = MATERIALS.fetch(name_of(r, g, b))
  def self.two_tone_of(r, g, b) = TWO_TONES.fetch(name_of(r, g, b))

  def self.name_of(r, g, b)
    BY_ALBEDO.min_by { |_name, (ar, ag, ab)| ((ar - r)**2) + ((ag - g)**2) + ((ab - b)**2) }.first
  end
end
