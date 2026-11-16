# Hooks for scripts/game (see README.md)
module GameCli
  def self.state
    game = Game.current
    performance = game.performance.map { |key, value| [key, value.round(2)] }.to_h
    {
      mode: game.mode, time_left: game.time_left.round(2), score: game.scoring.score,
      invaders: game.invaders.list.length, fps: GTK.current_framerate.round, boot_ms: game.boot_ms
    }.merge(performance)
  end

  # playing: a round starts; autopilot: a round plays itself (aims and fires at the nearest invader);
  # doom: autopilot with 6 seconds left; finale: autopilot just before the planet blows up
  def self.setup(name)
    game = Game.current
    case name
    when :playing then game.start_mode(:playing)
    when :autopilot
      game.start_mode(:playing)
      game.autopilot = true
    when :doom
      game.autopilot = true
      game.skip_to(6.0)
    when :finale
      game.autopilot = true
      game.skip_to(0.4)
    else raise "Unknown setup #{name}"
    end
  end
end
