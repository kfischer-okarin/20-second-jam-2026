# Screen-level juice: trauma based shake, directional kicks, hit-stop, flashes, chromatic aberration,
# slow motion and the shockwaves that the post shader turns into distortion rings
class Camera
  attr_reader :offset_x, :offset_y, :flash, :flash_color, :aberration, :trauma

  def initialize
    reset
  end

  def reset
    @time = 0.0
    @trauma = 0.0
    @offset_x = 0
    @offset_y = 0
    @kick_x = 0.0
    @kick_y = 0.0
    @hitstop = 0
    @flash = 0.0
    @flash_color = [1.0, 1.0, 1.0]
    @aberration = 0.0
    @waves = []
    @slow_scale = 1.0
    @slow_left = 0.0
  end

  def shake(amount)
    @trauma = [@trauma + amount, 1.0].min
  end

  def kick(dx, dy)
    @kick_x += dx
    @kick_y += dy
  end

  def freeze(frames)
    @hitstop = [@hitstop, frames].max
  end

  def frozen?
    @hitstop.positive?
  end

  def flash!(color, amount)
    return if amount < @flash

    @flash = amount
    @flash_color = color
  end

  def aberrate(amount)
    @aberration = [@aberration, amount].max
  end

  def slow_motion(scale, seconds)
    @slow_scale = scale
    @slow_left = seconds
  end

  def time_scale
    return 1.0 if @slow_left <= 0.0

    # eases back to full speed during the last half second
    @slow_scale + ((1.0 - @slow_scale) * (1.0 - [@slow_left / 0.5, 1.0].min))
  end

  def shockwave(x, y, speed:, strength:, life:)
    @waves << { x: x, y: y, age: 0.0, speed: speed, strength: strength, life: life }
  end

  # Runs in real time, also while the game is frozen
  def update(dt)
    @time += dt
    @hitstop -= 1 if @hitstop.positive?
    @slow_left -= dt
    @trauma = [@trauma - (dt * 1.25), 0.0].max
    amount = @trauma * @trauma * 7.0
    @offset_x = ((amount * shake_noise(@time * 31.0, 0.0)) + @kick_x).round
    @offset_y = ((amount * shake_noise(@time * 29.0, 4.7)) + @kick_y).round
    @kick_x *= 0.7
    @kick_y *= 0.7
    @flash = [@flash - (dt * 3.2), 0.0].max
    @aberration = [@aberration - (dt * 7.0), 0.0].max
    @waves.each do |wave|
      wave[:age] += dt
    end
    @waves.reject! { |wave| wave[:age] >= wave[:life] }
  end

  # [x, y, radius, strength] for each running shockwave, in scene pixels
  def wave_uniforms
    @waves.map do |wave|
      fade = 1.0 - (wave[:age] / wave[:life])
      [wave[:x] + @offset_x, wave[:y] + @offset_y, wave[:age] * wave[:speed], wave[:strength] * fade * fade]
    end
  end

  private

  def shake_noise(t, seed)
    (Math.sin(t + seed) * 0.6) + (Math.sin((t * 1.71) + (seed * 2.3)) * 0.4)
  end
end
