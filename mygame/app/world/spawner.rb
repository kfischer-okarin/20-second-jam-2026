# Decides when and where invaders appear and when plates break off the planet: a stream of invaders that
# thickens with doom, brutes and swarms at fixed moments, and plates breaking on a fixed schedule.
# Moments are given as seconds left on the clock.
class Spawner
  PLATE_SCHEDULE = [15.0, 12.0, 9.5, 7.5, 5.5, 4.0, 2.6, 1.4].freeze
  BRUTE_SCHEDULE = [13.5, 7.0].freeze
  SWARM_SCHEDULE = [10.5, 4.5].freeze
  TAU = Math::PI * 2

  def initialize(invaders)
    @invaders = invaders
    reset
  end

  def reset
    @plates_due = PLATE_SCHEDULE.dup
    @brutes_due = BRUTE_SCHEDULE.dup
    @swarms_due = SWARM_SCHEDULE.dup
    @spawn_timer = 1.0
  end

  def opening_wave(doom)
    [0.6, 2.4, 4.1].each do |theta|
      spawn(:drone, theta + (rand * 0.4), doom)
    end
  end

  # Forgets everything that would have been due before time_left
  def skip_to(time_left)
    [@plates_due, @brutes_due, @swarms_due].each do |schedule|
      schedule.select! { |due| due < time_left }
    end
  end

  # Spawns what is due and returns what happened, for the game to react to: one :plate for every plate that
  # should break, :brute and :swarm
  def update(dt, time_left, doom)
    events = []
    events << :plate while take_due(@plates_due, time_left)
    if take_due(@brutes_due, time_left)
      spawn(:brute, rand * TAU, doom)
      events << :brute
    end
    if take_due(@swarms_due, time_left)
      spawn_swarm(doom)
      events << :swarm
    end
    spawn_stream(dt, doom)
    events
  end

  private

  # Removes and returns the schedule's next moment once it has come, otherwise nil
  def take_due(schedule, time_left)
    schedule.shift if schedule.any? && time_left <= schedule.first
  end

  def spawn_stream(dt, doom)
    @spawn_timer -= dt
    return if @spawn_timer.positive?

    @spawn_timer = (1.0 - (0.7 * doom)) * (0.7 + (rand * 0.6))
    spawn(rand < 0.12 + (0.25 * doom) ? :saucer : :drone, rand * TAU, doom)
  end

  def spawn_swarm(doom)
    theta = rand * TAU
    7.times do |i|
      spawn(:drone, theta + ((i - 3) * 0.13), doom, extra_distance: (i % 3) * 9.0)
    end
  end

  # Just outside the edge of the screen, in direction theta from the planet in its center
  def spawn(type, theta, doom, extra_distance: 0.0)
    distance = edge_distance(theta) + 12.0 + extra_distance
    @invaders.spawn(type, theta, distance, speed_scale: 1.0 + (0.5 * doom))
  end

  def edge_distance(theta)
    cos = Math.cos(theta).abs
    sin = Math.sin(theta).abs
    half_w = PostProcess::W / 2.0
    half_h = PostProcess::H / 2.0
    [cos > 0.001 ? half_w / cos : 999.0, sin > 0.001 ? half_h / sin : 999.0].min
  end
end
