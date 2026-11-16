# Pixel font UI: countdown, score, combo meter, floating popups and the title and result screens
class Hud
  WHITE = [255, 255, 255].freeze
  YELLOW = [254, 231, 97].freeze
  ORANGE = [247, 118, 34].freeze
  RED = [255, 0, 68].freeze
  PINK = [246, 117, 122].freeze
  CYAN = [44, 232, 245].freeze
  GREY = [139, 155, 180].freeze
  DARK = [24, 20, 37].freeze
  COMBO_COLORS = [WHITE, YELLOW, ORANGE, PINK, RED, CYAN].freeze
  # Popups stay below the timer, score and combo
  HUD_BAND_Y = 142

  def initialize
    @popups = []
  end

  def clear
    @popups.clear
  end

  def popup(text, x, y, color: WHITE, scale: 1, life: 0.9, rise: 16.0)
    @popups << { text: text, x: x, y: y, color: color, scale: scale, life: life, age: 0.0, rise: rise }
  end

  def update(dt)
    @popups.each do |popup|
      popup[:age] += dt
      popup[:y] += popup[:rise] * dt * (1.0 - (popup[:age] / popup[:life]))
    end
    @popups.reject! { |popup| popup[:age] >= popup[:life] }
  end

  def render(game, camera)
    primitives = []
    shake_x = (camera.offset_x * 0.5).round
    shake_y = (camera.offset_y * 0.5).round
    render_popups(primitives, camera)
    case game.mode
    when :intro then render_intro(primitives, game)
    when :playing then render_playing(primitives, game, shake_x, shake_y)
    when :results then render_results(primitives, game)
    end
    primitives
  end

  private

  def render_popups(primitives, camera)
    @popups.each do |popup|
      progress = popup[:age] / popup[:life]
      next if progress > 0.7 && ((popup[:age] * 20).floor % 2).zero?

      scale = progress < 0.08 ? popup[:scale] + 1 : popup[:scale]
      half_width = (PixelFont.width(popup[:text], scale) / 2) + 2
      x = (popup[:x] + camera.offset_x).clamp(half_width, PostProcess::W - half_width)
      y = (popup[:y] + camera.offset_y).clamp(2, HUD_BAND_Y - (PixelFont::GLYPH_H * scale))
      text(primitives, popup[:text], x, y, scale: scale, color: popup[:color], align: :center)
    end
  end

  def render_intro(primitives, game)
    blink = ((game.mode_time * 2.5).floor % 2).zero?
    text(primitives, 'THE LAST 20 SECONDS', 160, 154, scale: 2, color: YELLOW, align: :center)
    text(primitives, 'OF A DYING WORLD', 160, 143, color: GREY, align: :center)
    text(primitives, 'CLICK OR PRESS A TO DEFEND IT', 160, 26, color: blink ? WHITE : YELLOW, align: :center)
    text(primitives, 'MOUSE AIMS - WASD/STICK MOVES - HOLD FIRE', 160, 12, color: GREY, align: :center)
  end

  def render_playing(primitives, game, shake_x, shake_y)
    render_timer(primitives, game, shake_x, shake_y)
    text(primitives, 'SCORE', 6, 170, color: GREY)
    text(primitives, game.scoring.score.to_s.rjust(7, '0'), 6, 160, color: WHITE)
    render_combo(primitives, game.scoring) if game.scoring.combo >= 2
  end

  def render_timer(primitives, game, shake_x, shake_y)
    time_left = [game.time_left, 0.0].max
    seconds = time_left.floor
    hundredths = ((time_left - seconds) * 100).floor
    label = "#{seconds.to_s.rjust(2, '0')}.#{hundredths.to_s.rjust(2, '0')}"
    tick = time_left - seconds > 0.85
    if time_left < 5.0
      color = tick ? WHITE : RED
      text(primitives, label, 160 + shake_x, 153 + shake_y, scale: 3, color: color, align: :center)
    else
      color = time_left < 10.0 ? ORANGE : YELLOW
      color = WHITE if game.penalty_flash.positive?
      text(primitives, label, 160 + shake_x, 158 + shake_y, scale: 2, color: color, align: :center)
    end
  end

  def render_combo(primitives, scoring)
    color = COMBO_COLORS[[scoring.multiplier - 1, COMBO_COLORS.length - 1].min]
    text(primitives, "x#{scoring.multiplier}", 314, 158, scale: 2, color: color, align: :right)
    text(primitives, "#{scoring.combo} CHAIN", 314, 148, color: GREY, align: :right)
    width = (40 * scoring.combo_fraction).round
    primitives << { x: 314 - width, y: 144, w: width, h: 2, path: :pixel, r: color[0], g: color[1], b: color[2] }
  end

  def render_results(primitives, game)
    scoring = game.scoring
    text(primitives, 'THE WORLD IS GONE', 160, 128, scale: 2, color: ORANGE, align: :center)
    text(primitives, "SCORE #{scoring.score}", 160, 100, scale: 2, color: WHITE, align: :center)
    if scoring.new_best && ((game.mode_time * 4).floor % 2).zero?
      text(primitives, 'NEW BEST!', 160, 88, color: YELLOW, align: :center)
    end
    text(primitives, "KILLS #{scoring.kills}   MAX CHAIN #{scoring.max_combo}", 160, 74, color: GREY, align: :center)
    text(primitives, "BEST #{scoring.best}", 160, 64, color: GREY, align: :center)
    return if game.mode_time < 1.2

    blink = ((game.mode_time * 2.5).floor % 2).zero?
    text(primitives, 'CLICK OR PRESS A TO TRY AGAIN', 160, 26, color: blink ? WHITE : YELLOW, align: :center)
  end

  def text(primitives, string, x, y, scale: 1, color: WHITE, align: :left)
    PixelFont.draw(primitives, string, x, y, scale: scale, color: color, align: align, outline: DARK)
  end
end
