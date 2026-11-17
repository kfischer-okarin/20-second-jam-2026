# Where things on the terrace appear on screen.
#
# World units are centimetres: x right, y up from the table top, z towards the viewer, the cup standing at the
# origin. The table is seen through a pinhole camera, so its boards converge, while every object on it is drawn
# with weak perspective: orthographically, at the scale and view angle of its footprint. That keeps the cup, the
# pitcher and the moka pot undistorted although the eye is much closer to them than it could be in reality.
#
# The camera is the eye's height above the table, its distance in front of the cup, its pitch below the
# horizontal and its focal length (in scene pixels). tilt, a vertical shift of the whole picture that stands in
# for looking up at the sky on the title screen, is not part of the projection: Terrace shifts its batches by it,
# so tilting draws nothing anew. The world beyond the table is a backdrop that hangs above the table's far edge
# (see World), not part of this projection either.
class View
  GAME = { height: 18.75, distance: 30.0, pitch: 0.445, focal: 362.0 }.freeze
  # Straight down onto the cup, for the ending
  TOP_DOWN = { height: 40.0, distance: 0.0, pitch: Math::PI / 2, focal: 390.0 }.freeze
  CENTER_X = 160.0
  CENTER_Y = 90.0
  TABLE_FAR_Z = -17.5

  attr_reader :height, :distance, :pitch, :focal
  attr_accessor :tilt

  def initialize
    @tilt = 0.0
    self.camera = GAME
  end

  def camera=(camera)
    @height = camera[:height]
    @distance = camera[:distance]
    @pitch = camera[:pitch]
    @focal = camera[:focal]
    @cos_pitch = Math.cos(@pitch)
    @sin_pitch = Math.sin(@pitch)
  end

  # Moves the camera between two others, t from 0 to 1
  def blend(start, finish, t)
    self.camera = start.map { |key, value| [key, value + ((finish[key] - value) * t)] }.to_h
  end

  # [screen_x, screen_y, scale, elevation] of the table point x, z: scale is pixels per centimetre there, and
  # elevation the angle at which the eye looks down at it, which foreshortens things lying on the table
  def ground(x, z)
    ahead = @distance - z
    forward = (ahead * @cos_pitch) + (@height * @sin_pitch)
    forward = 0.5 if forward < 0.5
    up = (ahead * @sin_pitch) - (@height * @cos_pitch)
    scale = @focal / forward
    sine = @height / forward
    elevation = sine >= 1.0 ? Math::PI / 2 : Math.asin(sine)
    [CENTER_X + (x * scale), CENTER_Y + (up * scale), scale, elevation]
  end

  # Screen position of a point y above the table point x, z, with the weak perspective of that footprint
  def point(x, y, z)
    sx, sy, scale, elevation = ground(x, z)
    [sx, sy + (y * scale * Math.cos(elevation)), scale, elevation]
  end

  # The point x, z on the plane at height y that shows at screen_x, screen_y (with the tilt): the inverse of point
  def unproject(screen_x, screen_y, y)
    screen_y -= @tilt
    z = 0.0
    6.times do
      _sx, sy, scale, elevation = point(0.0, y, z)
      z -= (screen_y - sy) / (scale * Math.sin(elevation).clamp(0.2, 1.0))
      z = z.clamp(-40.0, 40.0)
    end
    sx, _sy, scale, _elevation = point(0.0, y, z)
    [(screen_x - sx) / scale, z]
  end

  # Screen y of the table's far edge, where the world backdrop meets the table
  def horizon_y
    ground(0.0, TABLE_FAR_Z)[1]
  end
end
