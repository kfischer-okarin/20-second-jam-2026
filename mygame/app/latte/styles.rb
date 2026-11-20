# Looks for the game, to compare in the style lab (scripts/game reset lab, then left and right):
#   palette  the colors every pixel snaps to
#   dither   how much it dithers between the two nearest colors (0: flat bands)
#   bands    cel shading: [count, low, high] snaps the light on objects to count levels (see SplatRenderer)
#   ink      lines around objects: [r, g, b, width], or [:shade, factor, width] in a darker shade of their own
#            color (see SplatBatch)
#   smooth   evens out the mottle of neighboring splats over this many pixels before the palette (see PostProcess)
#   gloss    how much metal and glaze reflect (1: fully)
#   bloom    how much bright light blooms
#   ink_look draws the set pieces in two flat tones with ink lines, lit once by a sun from the left (see InkPieces)
#   bloom_solid lets the bright solid things bloom too, not only the glow layer
#   bright_threshold, vignette, saturation and shadow_tint grade the picture (see Game#grade)
module Styles
  # Ramps of seven or so steps for each of the terrace's materials
  RAMPS = [
    [18, 14, 22], [40, 32, 44],
    [54, 30, 28], [86, 48, 36], [122, 72, 48], [160, 102, 64], [196, 136, 88], [226, 172, 120], [244, 208, 160],
    [250, 236, 212], [255, 248, 236], [255, 255, 255],
    [255, 228, 168], [250, 200, 146], [236, 176, 136], [208, 182, 186], [176, 178, 204], [140, 156, 196],
    [104, 124, 176],
    [255, 196, 92], [255, 240, 170], [226, 112, 64],
    [26, 50, 42], [40, 80, 54], [62, 116, 62], [100, 152, 70], [150, 184, 90], [206, 210, 126],
    [28, 34, 62], [44, 56, 98], [66, 86, 136], [98, 124, 172],
    [58, 62, 74], [92, 98, 112], [130, 138, 154], [172, 180, 194], [212, 218, 228],
    [128, 76, 58], [180, 112, 82], [216, 152, 112], [240, 192, 154], [220, 128, 110]
  ].freeze

  # Shadow, middle and light for each material
  CEL = [
    [36, 28, 34],
    [82, 46, 36], [140, 86, 56], [198, 138, 90],
    [244, 228, 200], [255, 252, 244],
    [252, 222, 168], [214, 196, 196], [150, 166, 204], [255, 226, 140],
    [40, 54, 96], [72, 96, 148], [128, 154, 200],
    [78, 86, 104], [140, 150, 168], [206, 214, 226],
    [48, 92, 60], [110, 160, 80],
    [176, 110, 80], [230, 170, 128]
  ].freeze

  # Two clear tones for each material, white and a near black for the lines
  LIGNE_CLAIRE = [
    [24, 22, 30], [255, 255, 255], [246, 232, 206],
    [96, 54, 40], [184, 122, 78],
    [56, 80, 140], [120, 150, 204],
    [128, 138, 156], [210, 216, 228],
    [176, 110, 66], [222, 160, 104],
    [170, 200, 230], [250, 226, 180],
    [84, 150, 84]
  ].freeze

  # Strong, few colors
  BOLD = [
    [29, 22, 30], [98, 52, 38], [171, 100, 60], [230, 160, 100], [255, 236, 200], [255, 255, 255],
    [41, 64, 118], [98, 132, 196], [95, 102, 118], [194, 198, 210], [60, 130, 70], [255, 214, 110]
  ].freeze

  # Brown ink on cream paper, like the storyboard
  SEPIA = [[38, 26, 24], [84, 58, 46], [138, 102, 78], [190, 156, 120], [232, 210, 174], [252, 242, 222]].freeze
  # The same with the cup's blue as the only color
  SEPIA_BLUE = (SEPIA + [[52, 70, 120], [108, 136, 190], [255, 255, 255]]).freeze

  ALL = [
    { name: 'INK', ink_look: true, palette: [], dither: 0.0, smooth: 0, bloom: 0.3, bloom_solid: false,
      vignette: 0.12, saturation: 1.0, shadow_tint: 0.0 },
    { name: 'RAMPS', palette: RAMPS, dither: 0.0, smooth: 0, gloss: 1.0, bloom: 0.75 },
    { name: 'RAMPS SMOOTH', palette: RAMPS, dither: 0.0, smooth: 2, gloss: 0.6, bloom: 0.6 },
    { name: 'CEL', palette: CEL, dither: 0.0, smooth: 2, gloss: 0.35, bloom: 0.45 },
    { name: 'COMIC INK', palette: CEL, dither: 0.0, smooth: 2, gloss: 0.35, ink: [36, 28, 34, 1.0], bloom: 0.35 },
    { name: 'COLORED INK', palette: CEL, dither: 0.0, smooth: 2, gloss: 0.35, ink: [:shade, 0.42, 1.0],
      bloom: 0.35 },
    { name: 'LIGNE CLAIRE', palette: LIGNE_CLAIRE, dither: 0.0, smooth: 3, gloss: 0.2, bands: [2, 0.7, 1.25],
      ink: [24, 22, 30, 1.0], bloom: 0.2 },
    { name: 'BOLD', palette: BOLD, dither: 0.0, smooth: 3, gloss: 0.2, bands: [2, 0.65, 1.3],
      ink: [29, 22, 30, 1.6], bloom: 0.2 },
    { name: 'SEPIA', palette: SEPIA, dither: 0.0, smooth: 2, gloss: 0.3, ink: [38, 26, 24, 1.0], bloom: 0.3 },
    { name: 'SEPIA + BLUE', palette: SEPIA_BLUE, dither: 0.0, smooth: 2, gloss: 0.3, ink: [38, 26, 24, 1.0],
      bloom: 0.3 }
  ].freeze

  def self.default
    ALL.first
  end
end
