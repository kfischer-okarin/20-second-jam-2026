# Hooks for scripts/game (see README.md)
module GameCli
  def self.state
    game = Game.current
    terrace = game.terrace
    performance = game.performance.map { |key, value| [key, value.round(2)] }.to_h
    {
      state: game.state, state_time: game.state_time.round(2), level: terrace.coffee.level.round(2),
      foam: terrace.coffee.coverage.round(3), spilled: terrace.spills.spilled.round(2),
      pitcher: terrace.pitcher.mode, flow: terrace.pitcher.flow.round(2),
      fps: GTK.current_framerate.round, boot_ms: game.boot_ms
    }.merge(performance)
  end

  # play          pouring right away
  # heart         pouring right away, a heart by itself (also rosetta, spill)
  # art, face     the ending, after a heart
  # white         the white and the title coming back
  # lab           the style lab: the set pieces in one look after the other (left and right)
  def self.setup(name)
    game = Game.current
    case name
    when :play then game.skip_to_play
    when :lab then game.start_lab
    when :heart, :rosetta, :spill
      game.autopilot = Autopilot.new(name)
      game.skip_to_play
    when :art, :face, :white then game.skip_to_ending(name)
    else raise "Unknown setup #{name}"
    end
  end
end
