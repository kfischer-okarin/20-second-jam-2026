# The old wooden table: boards that run away from the eye towards the sun, projected through the View into the
# background layer. Each board is a run of solid trapezoids along its length, with grain streaks and knots as
# soft splats on top and dark seams between the boards. Its far edge, the seam with the world, catches the sun.
# The light falls from behind at a low angle, so the far boards glare where they reflect the sun, and the wave
# of light bleaches the table from its far edge (see #render).
#
# The wood keeps close to the palette's browns: a brown between two of them would dither into unrelated colors.
#
# A plain table (for the ink look) is one flat color, [r, g, b], without boards, grain, seams or glare.
class Table
  BOARD_WIDTH = 4.4
  BOARDS = 15
  NEAR_Z = 24.0
  STEP = 1.6
  TONES = [[192, 134, 100], [184, 124, 92], [198, 142, 106], [178, 120, 90], [190, 130, 96]].freeze
  DARK_GRAIN = [128, 76, 62].freeze
  LIGHT_GRAIN = [232, 172, 124].freeze
  SEAM = [62, 39, 49].freeze

  attr_accessor :plain

  def initialize
    @boards = TriangleBatch.new(:background)
    @edge = SplatBatch.new(:background, path: :pixel)
    @grain = SplatBatch.new(:background)
    @tones = Array.new(BOARDS) { |board| TONES[(Rng.at(3, board, :tone) * TONES.length).floor] }
    @noise = Noise3.new(8)
    @grain_strips = build_grain
    @seam_strips = build_seams
    @key = nil
  end

  def batches
    [@boards, @grain, @edge]
  end

  # Projects the boards again when the view or the light changed. light is [r, g, b] multiplying the wood, glare
  # how much the far boards reflect the sun, bleach_z the depth up to which the wave of light has bleached it
  def render(view, light, glare, bleach_z)
    key = [view.pitch.round(4), view.height.round(3), light.map { |c| (c * 30).round }, (glare * 30).round,
           bleach_z.round, @plain]
    return if key == @key

    @key = key
    @boards.clear
    @grain.clear
    @edge.clear
    camera = [view.height, view.distance, Math.cos(view.pitch), Math.sin(view.pitch), view.focal]
    draw_boards(camera, light, glare, bleach_z)
    unless @plain
      draw_strips(@grain, @grain_strips, camera, light, glare, bleach_z)
      draw_strips(@grain, @seam_strips, camera, light, glare * 0.2, bleach_z)
    end
    draw_far_edge(view, light)
  end

  private

  # Each board as trapezoids of STEP length, weathered unevenly along its length
  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def draw_boards(camera, light, glare, bleach_z)
    height, distance, cos_p, sin_p, focal = camera
    center_y = View::CENTER_Y
    far = View::TABLE_FAR_Z
    BOARDS.times do |board|
      left = board_x(board)
      right = left + BOARD_WIDTH
      tone = @tones[board]
      z = NEAR_Z
      while z > far
        z2 = z - STEP
        z2 = far if z2 < far
        near_forward = ((distance - z) * cos_p) + (height * sin_p)
        far_forward = ((distance - z2) * cos_p) + (height * sin_p)
        if near_forward > 1.0
          near_scale = focal / near_forward
          far_scale = focal / far_forward
          near_y = center_y + ((((distance - z) * sin_p) - (height * cos_p)) * near_scale)
          far_y = center_y + ((((distance - z2) * sin_p) - (height * cos_p)) * far_scale)
          if far_y > -5.0 && near_y < 190.0
            weather = 1.0 + (@noise.value(board * 4.0, z * 0.18, 0.5) * 0.12)
            r, g, b = wood(tone, weather, (z + z2) * 0.5, light, glare, bleach_z)
            @boards.add_quad(160.0 + (left * near_scale), near_y, 160.0 + (right * near_scale), near_y,
                             160.0 + (right * far_scale), far_y, 160.0 + (left * far_scale), far_y, r, g, b, 255)
          end
        end
        z = z2
      end
    end
  end

  def wood(tone, weather, z, light, glare, bleach_z)
    depth = ((z - View::TABLE_FAR_Z) / 14.0).clamp(0.0, 1.0)
    shine = glare * (1.0 - depth) * (1.0 - depth)
    wash = z < bleach_z ? ((bleach_z - z) / 6.0).clamp(0.0, 1.0) : 0.0
    Array.new(3) do |c|
      lit = @plain ? @plain[c].to_f : (tone[c] * weather * light[c]) + (shine * [255.0, 225.0, 170.0][c])
      (lit + (([255.0, 255.0, 250.0][c] - lit) * wash)).clamp(0, 255)
    end
  end

  def board_x(board)
    (board - (BOARDS * 0.5)) * BOARD_WIDTH
  end

  def build_grain
    noise = Noise3.new(5)
    strips = []
    BOARDS.times do |board|
      left = board_x(board)
      7.times do |line|
        across = 0.1 + (line * 0.13) + (Rng.at(board, line, :across) * 0.05)
        z = NEAR_Z - (Rng.at(board, line, :start) * 3.0)
        while z > View::TABLE_FAR_Z + 1.5
          length = 2.0 + (Rng.at(board, (line * 97) + z.round, :length) * 3.5)
          wave = noise.value((board * 5.0) + line, z * 0.2, 1.0) * 0.25
          x = left + ((across + (wave * 0.15)) * BOARD_WIDTH)
          dark = noise.value(board * 3.0, line * 2.0, z * 0.15).positive?
          color = dark ? DARK_GRAIN : LIGHT_GRAIN
          strips << [x, z - (length * 0.5), length, 0.18 + (Rng.at(board, line, :width) * 0.14), *color,
                     dark ? 120 : 70]
          z -= length + (Rng.at(board, (line * 31) + z.round, :gap) * 2.0)
        end
      end
      add_knots(strips, board, left)
    end
    strips
  end

  def add_knots(strips, board, left)
    2.times do |i|
      next if Rng.at(board, i, :knot) < 0.45

      z = View::TABLE_FAR_Z + 2.0 + (Rng.at(board, i, :knot_z) * 36.0)
      x = left + ((0.25 + (Rng.at(board, i, :knot_x) * 0.5)) * BOARD_WIDTH)
      strips << [x, z, 1.4, 0.7, *DARK_GRAIN, 210]
      strips << [x, z, 0.7, 0.35, *SEAM, 200]
    end
  end

  def build_seams
    strips = []
    (BOARDS + 1).times do |board|
      x = board_x(board)
      z = NEAR_Z
      while z > View::TABLE_FAR_Z + 0.6
        strips << [x, z - 1.5, 3.4, 0.24, *SEAM, 255]
        z -= 3.0
      end
    end
    strips
  end

  # Hot loop over the strips
  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def draw_strips(batch, strips, camera, light, glare, bleach_z)
    height, distance, cos_p, sin_p, focal = camera
    lr, lg, lb = light
    center_y = View::CENTER_Y
    center_x = View::CENTER_X
    far = View::TABLE_FAR_Z
    i = 0
    count = strips.length
    while i < count
      x, z, length, width, r, g, b, a = strips[i]
      i += 1
      ahead = distance - z
      forward = (ahead * cos_p) + (height * sin_p)
      next if forward < 1.0

      scale = focal / forward
      sx = center_x + (x * scale)
      next if sx < -60.0 || sx > 380.0

      up = (ahead * sin_p) - (height * cos_p)
      sy = center_y + (up * scale)
      next if sy < -30.0 || sy > 210.0

      # The strip's far end, for its length and direction on screen
      ahead2 = ahead + (length * 0.5)
      forward2 = (ahead2 * cos_p) + (height * sin_p)
      scale2 = focal / forward2
      ahead3 = ahead - (length * 0.5)
      forward3 = (ahead3 * cos_p) + (height * sin_p)
      forward3 = 0.5 if forward3 < 0.5
      scale3 = focal / forward3
      dx = (x * scale2) - (x * scale3)
      dy = (((ahead2 * sin_p) - (height * cos_p)) * scale2) - (((ahead3 * sin_p) - (height * cos_p)) * scale3)
      on_screen = Math.sqrt((dx * dx) + (dy * dy))
      angle = Math.atan2(dy, dx) * SplatRenderer::RAD_TO_DEG
      depth = ((z - far) / 14.0).clamp(0.0, 1.0)
      shine = glare * (1.0 - depth) * (1.0 - depth)
      wash = z < bleach_z ? ((bleach_z - z) / 6.0).clamp(0.0, 1.0) : 0.0
      cr = (r * lr) + (shine * 255.0)
      cg = (g * lg) + (shine * 225.0)
      cb = (b * lb) + (shine * 170.0)
      cr += (255.0 - cr) * wash
      cg += (255.0 - cg) * wash
      cb += (250.0 - cb) * wash
      batch.add(sx, sy, on_screen, width * scale, angle, cr.clamp(0, 255), cg.clamp(0, 255), cb.clamp(0, 255), a)
    end
  end

  # The far edge of the table catches the sun as a bright line
  def draw_far_edge(view, light)
    y = view.horizon_y
    brightness = (0.75 + (light[0] * 0.3)).clamp(0.0, 1.3)
    @edge.add(160.0, y - 0.5, 400.0, 1.5, 0.0, 255 * brightness, 214 * brightness, 160 * brightness, 255)
  end
end
