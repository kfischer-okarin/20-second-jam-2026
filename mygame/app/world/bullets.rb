# The turret's plasma bolts
class Bullets
  SPEED = 240.0
  LIFE = 1.6
  HIT_MARGIN = 1.5

  attr_reader :list

  def initialize
    @list = []
    @batch = SplatBatch.new(:glow)
  end

  def clear
    @list.clear
  end

  # dx, dy is the unit direction to fly in
  def fire(x, y, dx, dy)
    @list << { x: x, y: y, vx: dx * SPEED, vy: dy * SPEED, age: 0.0 }
  end

  def update(dt)
    @list.each do |bullet|
      bullet[:age] += dt
      bullet[:x] += bullet[:vx] * dt
      bullet[:y] += bullet[:vy] * dt
    end
    @list.reject! { |bullet| bullet[:age] > LIFE || bullet[:x].abs > 400 || bullet[:y] < -60 || bullet[:y] > 240 }
  end

  # Removes every bullet that hits one of the invaders and yields that invader and the bullet
  def collide(invaders)
    @list.reject! do |bullet|
      target = invaders.find { |invader|
        reach = invader[:radius] + HIT_MARGIN
        ((invader[:x] - bullet[:x])**2) + ((invader[:y] - bullet[:y])**2) < reach * reach
      }
      next false unless target

      yield target, bullet
      true
    end
  end

  # A white-hot head with a cyan streak behind it
  def render
    batch = @batch
    batch.clear
    @list.each do |bullet|
      angle = Math.atan2(bullet[:vy], bullet[:vx]) * SplatRenderer::RAD_TO_DEG
      tail_x = bullet[:x] - (bullet[:vx] / SPEED * 4.0)
      tail_y = bullet[:y] - (bullet[:vy] / SPEED * 4.0)
      batch.add(tail_x, tail_y, 12.0, 3.0, angle, 20, 120, 200, 255)
      batch.add(bullet[:x], bullet[:y], 7.0, 3.0, angle, 120, 240, 255, 255)
      batch.add(bullet[:x], bullet[:y], 3.0, 2.0, angle, 255, 255, 255, 255)
    end
    batch
  end
end
