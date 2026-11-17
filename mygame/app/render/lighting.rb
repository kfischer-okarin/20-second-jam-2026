# Light that falls on splats: a directional sun, ambient, a rim light on edges and point lights.
# Colors are multipliers of a splat's albedo (1.0 shows the albedo unchanged).
#
# Ambient is a hemisphere: surfaces facing up (along up) get ambient, surfaces facing down get ground, the bounce
# light from below. Without ground, ambient is the same from all sides.
# Glossy splats (SplatModel#aux, see SplatRenderer) reflect an environment instead: ahead of the eye sky above the
# horizon and floor below it, behind the eye (where reflections that face the eye look) behind, and a glare of
# the sun's color around the sun's direction.
# Directions are in view space (x right, y up, z towards the viewer), so a game that looks at things from above
# turns up and sun with its view.
class Lighting
  attr_reader :sun, :up, :points
  attr_accessor :sun_color, :ambient, :ground, :rim, :sky, :floor, :behind

  # sun is the direction towards the sun, normalized here
  def initialize(sun: [-0.5, 0.6, 0.6], sun_color: [1.0, 1.0, 1.0], ambient: [0.2, 0.2, 0.2], rim: [0.0, 0.0, 0.0],
                 ground: nil, up: [0.0, 1.0, 0.0], sky: nil, floor: nil, behind: nil)
    self.sun = sun
    self.up = up
    @sun_color = sun_color
    @ambient = ambient
    @ground = ground || ambient
    @rim = rim
    @sky = sky || ambient
    @floor = floor || @ground
    @behind = behind || @sky
    @points = []
  end

  def sun=(direction)
    @sun = normalize(*direction)
  end

  def up=(direction)
    @up = normalize(*direction)
  end

  # Point lights are [x, y, z, r, g, b, radius, except] in scene pixels. except names a receiver that the light
  # leaves unlit (see points_near), such as the thing it shines out of.
  def add_point(x, y, z, r, g, b, radius, except: nil)
    @points << [x, y, z, r, g, b, radius, except]
  end

  def clear_points
    @points.clear
  end

  # The point lights that can reach a circle around x, y, without those that leave the receiver unlit
  def points_near(x, y, radius, receiver: nil)
    @points.select do |light|
      next false if receiver && light[7] == receiver

      reach = light[6] + radius
      ((light[0] - x)**2) + ((light[1] - y)**2) < reach * reach
    end
  end

  private

  def normalize(x, y, z)
    length = Math.sqrt((x * x) + (y * y) + (z * z))
    [x / length, y / length, z / length]
  end
end
