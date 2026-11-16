# A 5x7 bitmap font baked into a pixel array, so text sits on the same pixel grid as the rest of the scene
module PixelFont
  GLYPH_W = 5
  GLYPH_H = 7
  ADVANCE = 6

  GLYPHS = {
    ' ' => %w[..... ..... ..... ..... ..... ..... .....],
    '0' => %w[.###. #...# #..## #.#.# ##..# #...# .###.],
    '1' => %w[..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###.],
    '2' => %w[.###. #...# ....# ...#. ..#.. .#... #####],
    '3' => %w[##### ...#. ..#.. ...#. ....# #...# .###.],
    '4' => %w[...#. ..##. .#.#. #..#. ##### ...#. ...#.],
    '5' => %w[##### #.... ####. ....# ....# #...# .###.],
    '6' => %w[..##. .#... #.... ####. #...# #...# .###.],
    '7' => %w[##### ....# ...#. ..#.. .#... .#... .#...],
    '8' => %w[.###. #...# #...# .###. #...# #...# .###.],
    '9' => %w[.###. #...# #...# .#### ....# ...#. .##..],
    'A' => %w[.###. #...# #...# ##### #...# #...# #...#],
    'B' => %w[####. #...# #...# ####. #...# #...# ####.],
    'C' => %w[.###. #...# #.... #.... #.... #...# .###.],
    'D' => %w[###.. #..#. #...# #...# #...# #..#. ###..],
    'E' => %w[##### #.... #.... ####. #.... #.... #####],
    'F' => %w[##### #.... #.... ####. #.... #.... #....],
    'G' => %w[.###. #...# #.... #.### #...# #...# .####],
    'H' => %w[#...# #...# #...# ##### #...# #...# #...#],
    'I' => %w[.###. ..#.. ..#.. ..#.. ..#.. ..#.. .###.],
    'J' => %w[..### ...#. ...#. ...#. ...#. #..#. .##..],
    'K' => %w[#...# #..#. #.#.. ##... #.#.. #..#. #...#],
    'L' => %w[#.... #.... #.... #.... #.... #.... #####],
    'M' => %w[#...# ##.## #.#.# #.#.# #...# #...# #...#],
    'N' => %w[#...# #...# ##..# #.#.# #..## #...# #...#],
    'O' => %w[.###. #...# #...# #...# #...# #...# .###.],
    'P' => %w[####. #...# #...# ####. #.... #.... #....],
    'Q' => %w[.###. #...# #...# #...# #.#.# #..#. .##.#],
    'R' => %w[####. #...# #...# ####. #.#.. #..#. #...#],
    'S' => %w[.#### #.... #.... .###. ....# ....# ####.],
    'T' => %w[##### ..#.. ..#.. ..#.. ..#.. ..#.. ..#..],
    'U' => %w[#...# #...# #...# #...# #...# #...# .###.],
    'V' => %w[#...# #...# #...# #...# #...# .#.#. ..#..],
    'W' => %w[#...# #...# #...# #.#.# #.#.# #.#.# .#.#.],
    'X' => %w[#...# #...# .#.#. ..#.. .#.#. #...# #...#],
    'Y' => %w[#...# #...# .#.#. ..#.. ..#.. ..#.. ..#..],
    'Z' => %w[##### ....# ...#. ..#.. .#... #.... #####],
    '.' => %w[..... ..... ..... ..... ..... .##.. .##..],
    ':' => %w[..... .##.. .##.. ..... .##.. .##.. .....],
    '-' => %w[..... ..... ..... .###. ..... ..... .....],
    '+' => %w[..... ..#.. ..#.. ##### ..#.. ..#.. .....],
    'x' => %w[..... ..... #...# .#.#. ..#.. .#.#. #...#],
    '!' => %w[..#.. ..#.. ..#.. ..#.. ..#.. ..... ..#..],
    '/' => %w[....# ....# ...#. ..#.. .#... #.... #....],
    '?' => %w[.###. #...# ....# ...#. ..#.. ..... ..#..]
  }.freeze

  CHARS = GLYPHS.keys.freeze
  INDEX = CHARS.each_with_index.map { |char, index| [char, index] }.to_h.freeze

  extend self

  def create_atlas(args)
    width = CHARS.length * ADVANCE
    pixels = Array.new(width * GLYPH_H, 0)
    CHARS.each_with_index do |char, glyph_index|
      GLYPHS[char].each_with_index do |row, y|
        row.each_char.with_index do |cell, x|
          pixels[(y * width) + (glyph_index * ADVANCE) + x] = 0xFFFFFFFF if cell == '#'
        end
      end
    end
    pixel_array = args.pixel_array(:font)
    pixel_array.w = width
    pixel_array.h = GLYPH_H
    pixel_array.pixels = pixels
  end

  def width(text, scale = 1)
    ((text.length * ADVANCE) - 1) * scale
  end

  # Appends one sprite per character to primitives. x/y is the bottom left corner unless align says otherwise.
  # The outline color draws a one pixel border around every glyph.
  def draw(primitives, text, x, y, scale: 1, color: [255, 255, 255], alpha: 255, align: :left, outline: nil)
    x -= width(text, scale) / 2 if align == :center
    x -= width(text, scale) if align == :right
    x = x.round
    y = y.round
    if outline
      [[-1, 0], [1, 0], [0, -1], [0, 1], [1, -1]].each do |dx, dy|
        glyphs(primitives, text, x + dx, y + dy, scale, outline, alpha)
      end
    end
    glyphs(primitives, text, x, y, scale, color, alpha)
  end

  def glyphs(primitives, text, x, y, scale, color, alpha)
    text.each_char.with_index do |char, i|
      index = INDEX[char] || INDEX['?']
      next if char == ' '

      primitives << {
        x: x + (i * ADVANCE * scale), y: y, w: GLYPH_W * scale, h: GLYPH_H * scale,
        path: :font, source_x: index * ADVANCE, source_y: 0, source_w: GLYPH_W, source_h: GLYPH_H,
        r: color[0], g: color[1], b: color[2], a: alpha
      }
    end
  end
end
