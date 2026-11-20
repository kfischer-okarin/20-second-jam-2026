# The milk pitcher, which is the player's cursor: it floats where the player aims "as if moved by magic", at a
# height and a tilt of the player's choosing, and pours once the milk reaches its lip.
#
# Its model's origin is the tip of the spout, so it tilts around the point it pours from. Milk leaves the spout
# as parcels that keep some of the pitcher's motion and fall under gravity, which bends the stream when the
# pitcher moves; each parcel lands on whatever is below it (see Game#land).
class Pitcher
  BOTTOM = [3.4, -6.3, 0.0].freeze
  SPOUT_BASE = [2.1, -1.0, 0.0].freeze
  SPOUT_TIP = [0.3, 0.0, 0.0].freeze
  # Half the wall's thickness, the height of the rolled rim above the bottom and the radius it runs at (the middle
  # of the wall there)
  WALL = 0.25
  RIM = 5.85
  RIM_RADIUS = 1.99
  MILK_Y = 4.6
  # The spout points left and a little towards the eye, so that its body stays right of the art and behind it,
  # and its beak shows in profile
  YAW = 0.35
  # Where its bottom stands on the table while nobody holds it
  REST = [10.8, 0.0, 2.2].freeze
  # Height of the spout above the coffee
  LOWEST = 0.5
  HIGHEST = 7.5
  START_HEIGHT = 4.5
  # Tilt (radians around the spout) at which milk reaches the lip, and the most it tilts
  LIP_TILT = 0.5
  MAX_TILT = 1.45
  GRAVITY = 520.0
  # How far the aim can go, in centimetres around the cup
  AIM_BOUNDS = [-15.0, -11.0, 17.0, 13.0].freeze
  FOLLOW = 13.0

  attr_reader :x, :y, :z, :tilt, :flow, :parcels, :mode, :height

  # The can's wall, cut open at the rim
  def self.wall(x, y, z)
    shell = can(x, y, z).abs - WALL
    cut = y - BOTTOM[1] - RIM
    # rubocop:disable-next Style/MinMaxComparison
    shell > cut ? shell : cut
  end

  # The middle of the can's wall: a frustum rounded off by 0.6, from WALL above the bottom to above the rim, so
  # that the cut opens it. Outside, its radius is 2.6 at the bottom and 2.24 at the rim.
  def self.can(x, y, z)
    Sdf.capped_cone(x - BOTTOM[0], y - BOTTOM[1] - 3.6, z, 2.75, 1.75, 1.35) - 0.6
  end

  # A beak that sticks out well beyond the rim and rises above it, open along the top into a channel towards the
  # tip at the origin
  def self.spout(x, y, z)
    beak = Sdf.cone_between(x, y, z, SPOUT_BASE, SPOUT_TIP, 1.0, 0.3).abs - 0.2
    open_top = ((x - SPOUT_BASE[0]) * 0.486) + ((y - SPOUT_BASE[1]) * 0.874) - 0.05
    # rubocop:disable-next Style/MinMaxComparison
    beak > open_top ? beak : open_top
  end

  # The inside below the milk never shows
  def self.visible_surface?(x, y, z)
    can(x, y, z).positive? || y - BOTTOM[1] > MILK_Y + 0.1
  end

  def initialize
    @mode = :rest
    @x, @y, @z = rest_spout
    @vx = 0.0
    @vy = 0.0
    @vz = 0.0
    @tilt = 0.0
    @tilt_set = 0.0
    @flow = 0.0
    @height = START_HEIGHT
    @parcels = []
    @time = 0.0
    @poured = 0.0
  end

  # Seconds of full flow poured so far
  attr_reader :poured

  def rotation
    Rot3.mul(Rot3.rot_y(YAW), Rot3.rot_z(@tilt))
  end

  def rest_spout
    bx, by, bz = Rot3.apply(Rot3.rot_y(YAW), *BOTTOM)
    [REST[0] - bx, REST[1] - by, REST[2] - bz]
  end

  # Rises off the table into the player's hands
  def take
    @mode = :rising
    @mode_time = 0.0
    @from = [@x, @y, @z]
  end

  # Settles back onto the table
  def put_down
    @mode = :settling
    @mode_time = 0.0
    @from = [@x, @y, @z]
    @from_tilt = @tilt
  end

  def held?
    @mode == :held
  end

  # controls: aim_x, aim_z (where to pour, on the coffee's plane), raise (-1..1), tip (-1..1), pour (held),
  # surface (height of the coffee)
  def update(dt, controls, surface)
    @time += dt
    case @mode
    when :held then steer(dt, controls, surface)
    when :rising then rise(dt, controls, surface)
    when :settling then settle(dt)
    end
    @flow = held? ? flow_at(@tilt) : 0.0
    @poured += @flow * dt
    emit
    fall(dt)
  end

  # Removes the parcels that fell below the height that floor returns for their x, z, and returns them as
  # [x, z, flow, fall, speed_x, speed_z, floor]: fall is the height they fell from, speed how fast the stream
  # moved where they left the spout
  def landed(&floor)
    landed = []
    @parcels.reject! do |parcel|
      ground = floor.call(parcel[0], parcel[2])
      next false if parcel[1] > ground

      landed << [parcel[0], parcel[2], parcel[6], parcel[7] - ground, parcel[8], parcel[9], ground]
      true
    end
    landed
  end

  private

  def flow_at(tilt)
    t = ((tilt - LIP_TILT) / (MAX_TILT - LIP_TILT)).clamp(0.0, 1.0)
    t**1.3
  end

  # controls[:height] and controls[:tilt], when given, set them directly (see Autopilot)
  def steer(dt, controls, surface)
    @height = (@height + (controls[:raise] * dt * 7.0)).clamp(LOWEST, HIGHEST)
    @height = controls[:height] if controls[:height]
    left, bottom, right, top = AIM_BOUNDS
    target_x = controls[:aim_x].clamp(left, right)
    target_z = controls[:aim_z].clamp(bottom, top)
    bob = Math.sin(@time * 1.7) * 0.08
    follow(dt, target_x, surface + @height + bob, target_z)
    steer_tilt(dt, controls)
  end

  # The mouse button tips it progressively while held and lets it swing back when released; the keys set a
  # tilt that stays
  def steer_tilt(dt, controls)
    @tilt_set = (@tilt_set + (controls[:tip] * dt * 0.7)).clamp(0.0, MAX_TILT)
    @tilt_set = controls[:tilt] if controls[:tilt]
    target = @tilt_set
    if controls[:pour]
      @hold = (@hold || 0.0) + dt
      target = [target, LIP_TILT + 0.05 + (@hold * 0.55)].max
    else
      @hold = 0.0
    end
    target = target.clamp(0.0, MAX_TILT)
    rate = target > @tilt ? 3.0 : 4.0
    @tilt += (target - @tilt) * [rate * dt, 1.0].min
  end

  # A critically damped spring, which gives it a soft, floating weight
  def follow(dt, target_x, target_y, target_z)
    stiffness = FOLLOW * FOLLOW
    damping = 2.0 * FOLLOW
    @vx += (((target_x - @x) * stiffness) - (@vx * damping)) * dt
    @vy += (((target_y - @y) * stiffness) - (@vy * damping)) * dt
    @vz += (((target_z - @z) * stiffness) - (@vz * damping)) * dt
    @x += @vx * dt
    @y += @vy * dt
    @z += @vz * dt
  end

  def rise(dt, controls, surface)
    @mode_time += dt
    t = (@mode_time / 1.6).clamp(0.0, 1.0)
    ease = t * t * (3.0 - (2.0 * t))
    lift = Math.sin(t * Math::PI) * 4.0
    fx, fy, fz = @from
    target_x = controls[:aim_x].clamp(-6.0, 6.0)
    target_z = controls[:aim_z].clamp(-4.0, 4.0)
    @x = fx + ((target_x - fx) * ease)
    @y = fy + ((surface + @height - fy) * ease) + lift
    @z = fz + ((target_z - fz) * ease)
    @mode = :held if t >= 1.0
  end

  def settle(dt)
    @mode_time += dt
    t = (@mode_time / 1.4).clamp(0.0, 1.0)
    ease = t * t * (3.0 - (2.0 * t))
    fx, fy, fz = @from
    rx, ry, rz = rest_spout
    lift = Math.sin(t * Math::PI) * 2.5
    @x = fx + ((rx - fx) * ease)
    @y = fy + ((ry - fy) * ease) + lift
    @z = fz + ((rz - fz) * ease)
    @tilt = @from_tilt * (1.0 - ease)
    @vx = 0.0
    @vy = 0.0
    @vz = 0.0
    @mode = :rest if t >= 1.0
  end

  # A parcel is [x, y, z, vx, vy, vz, flow, start_y, speed_x, speed_z]: it keeps some of the pitcher's motion
  def emit
    return if @flow <= 0.0

    @parcels << [@x, @y, @z, @vx * 0.45, 0.0, @vz * 0.45, @flow, @y, @vx, @vz]
  end

  def fall(dt)
    @parcels.each do |parcel|
      parcel[4] -= GRAVITY * dt
      parcel[0] += parcel[3] * dt
      parcel[1] += parcel[4] * dt
      parcel[2] += parcel[5] * dt
    end
  end
end
