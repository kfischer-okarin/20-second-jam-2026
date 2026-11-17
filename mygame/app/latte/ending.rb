# The ending, where control passes back to him:
#   art   the camera turns straight down onto the cup, the art glows in the light, his hand comes in, takes the
#         cup by its handle and lifts it out of frame
#   face  his face, the first time we see him: he has just lowered the cup from his lips, eyes closed, smiling
class Ending
  # The forearm comes from the lower left
  HAND_YAW = 0.62
  # Where the fingertips hook the handle, in the hand model's space, and where the handle is on the cup
  FINGERTIPS = [2.3, -1.1, 0.0].freeze
  HANDLE = [-6.75, 3.9, 0.0].freeze
  LIFT_TO = [-17.0, 26.0, 13.0].freeze
  FACE_SCALE = 4.3
  FACE_CENTER = [160.0, 106.0].freeze

  def initialize
    @hand_batch = SplatBatch.new(:solid, path: :disc)
    @face = {
      back: SplatBatch.new(:background), body: SplatBatch.new(:solid, path: :disc),
      head: SplatBatch.new(:solid, path: :disc), cup: SplatBatch.new(:solid, path: :disc),
      fist: SplatBatch.new(:solid, path: :disc), latte: SplatBatch.new(:solid, path: :disc),
      light: SplatBatch.new(:glow)
    }
    @lighting = Lighting.new
  end

  # --- E1: the art -------------------------------------------------------------------------------------------------

  def start_art(terrace)
    @terrace = terrace
    @hand_reach = 0.0
    @lifted = false
  end

  def update_art(terrace, t, _dt)
    turn = smootherstep((t / 2.8).clamp(0.0, 1.0))
    terrace.view.blend(View::GAME, View::TOP_DOWN, turn)
    terrace.view.tilt = 0.0
    terrace.light_progress = 2.1 + (t * 0.05)
    terrace.cup_glow = ((t - 1.2) / 2.0).clamp(0.0, 1.0) * 0.55
    @hand_reach = smootherstep(((t - 2.9) / 1.5).clamp(0.0, 1.0))
    lift = smootherstep(((t - 4.9) / 2.2).clamp(0.0, 1.0))
    if lift.positive?
      unless @lifted
        yield :clink
        @lifted = true
      end
      terrace.cup_lift = [LIFT_TO[0] * lift, Cup::BASE_Y + (LIFT_TO[1] * lift * lift), LIFT_TO[2] * lift]
    end
    terrace.hidden[:pitcher] = false
  end

  def hand_batches
    batch = @hand_batch
    batch.clear
    return [batch] if @hand_reach <= 0.0

    rotation = Rot3.rot_y(HAND_YAW)
    grip = grip_point
    tip = Rot3.apply(rotation, *FINGERTIPS)
    away = (1.0 - @hand_reach) * 26.0
    origin = [grip[0] - tip[0] - (away * 0.83), grip[1] - tip[1] + (away * 0.15), grip[2] - tip[2] + (away * 0.56)]
    sx, sy, scale, elevation = @terrace.lifted_point(*origin)
    matrix = Rot3.mul(Rot3.rot_x(elevation), rotation)
    SplatRenderer.render(batch, EndingModels.hand, matrix, sx, sy, 0.0, scale, @terrace.light_for(elevation))
    [batch]
  end

  # --- E2: his face ------------------------------------------------------------------------------------------------

  def start_face
    @face_time = 0.0
    @face_drawn = false
    @cup_settled = false
  end

  def update_face(t, _dt)
    @face_time = t
  end

  # He holds still but for his breath, so he is drawn once and then only moved; the cup until it settles
  def face_batches
    t = @face_time
    light = face_light
    draw_face(light) unless @face_drawn
    render_face_light(t)
    breath = Math.sin(t * 1.4) * 0.6
    @face[:body].shift_y = breath.round
    @face[:head].shift_y = (breath * 0.7).round
    render_cup(t, light) unless @cup_settled
    @cup_settled = t > 1.7
    %i[back body head cup latte fist light].map { |name| @face[name] }
  end

  def draw_face(light)
    cx, cy = FACE_CENTER
    @face[:body].clear
    SplatRenderer.render(@face[:body], EndingModels.body, Rot3.rot_x(0.05), cx, cy, 0.0, FACE_SCALE, light)
    @face[:head].clear
    tilt = Rot3.mul(Rot3.rot_x(0.07), Rot3.rot_z(0.03))
    SplatRenderer.render(@face[:head], EndingModels.head, tilt, cx, cy, 0.0, FACE_SCALE, light)
    @face_drawn = true
  end

  # Post-processing of the ending: the light keeps growing
  def grade(post, state, t)
    if state == :art
      post.exposure = 1.0 + (t * 0.015)
      post.bloom = 1.0
      post.bright_threshold = 0.72
    else
      post.background_color = [254, 240, 214]
      post.exposure = 1.0
      post.bloom = 0.45
      post.bright_threshold = 0.82
      post.vignette = 0.0
    end
  end

  private

  def smootherstep(t)
    t * t * t * ((t * ((t * 6.0) - 15.0)) + 10.0)
  end

  def grip_point
    x, y, z = @terrace.cup_lift || [0.0, Cup::BASE_Y, 0.0]
    [x + HANDLE[0], y + HANDLE[1], z + HANDLE[2]]
  end

  # The wave of light is behind the eye now, so it falls straight onto him: warm and soft, from a little above
  # and to the left, with a cooler fill from the sky
  def face_light
    lighting = @lighting
    lighting.sun = [-0.35, 0.45, 0.82]
    lighting.up = [0.0, 1.0, 0.0]
    lighting.sun_color = [0.72, 0.62, 0.5]
    lighting.ambient = [0.5, 0.5, 0.54]
    lighting.ground = [0.36, 0.3, 0.26]
    lighting.rim = [0.4, 0.36, 0.3]
    lighting.sky = [1.2, 1.15, 1.1]
    lighting.floor = [0.6, 0.5, 0.42]
    lighting.behind = [1.0, 0.95, 0.88]
    lighting
  end

  def render_face_light(t)
    back = @face[:back]
    back.clear
    6.times do |i|
      x = 160.0 + (Math.sin((t * 0.3) + i) * 120.0)
      back.add(x, 90.0 + (Math.cos((t * 0.4) + (i * 2.0)) * 60.0), 200.0, 160.0, 0.0, 255, 252, 240, 120)
    end
    glow = @face[:light]
    glow.clear
    glow.add(160.0, 150.0, 320.0, 120.0, 0.0, 60, 56, 44, 255)
  end

  # He has just lowered the cup from his lips: it settles in his hand in front of his chest
  def render_cup(t, light)
    lower = smootherstep((t / 1.6).clamp(0.0, 1.0))
    x = 205.0 + ((1.0 - lower) * -38.0)
    y = 20.0 + ((1.0 - lower) * 52.0)
    tip = (1.0 - lower) * 0.5
    matrix = Rot3.mul(Rot3.rot_x(0.32), Rot3.mul(Rot3.rot_z(-tip), Rot3.rot_y(Math::PI)))
    @face[:cup].clear
    SplatRenderer.render(@face[:cup], Models.cup, matrix, x, y, 0.0, FACE_SCALE, light)
    latte = @face[:latte]
    latte.clear
    surface_y = y + (3.6 * FACE_SCALE * Math.cos(0.32))
    latte.add(x, surface_y, 8.6 * FACE_SCALE, 8.6 * FACE_SCALE * Math.sin(0.32), Math.sin(tip) * 30.0, 196, 150,
              112, 255)
    latte.add(x - 4.0, surface_y + 1.0, 4.0 * FACE_SCALE, 1.2 * FACE_SCALE, 0.0, 240, 232, 220, 255)
    handle_x = x + (6.75 * FACE_SCALE)
    handle_y = y + (3.9 * FACE_SCALE * Math.cos(0.32))
    @face[:fist].clear
    SplatRenderer.render(@face[:fist], EndingModels.fist, Rot3.rot_x(0.2), handle_x, handle_y, 0.0, FACE_SCALE, light)
  end
end
