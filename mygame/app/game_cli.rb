# Hooks for scripts/game (see README.md)
module GameCli
  def self.state
    game = Game.current
    performance = game.performance.map { |key, value| [key, value.round(2)] }.to_h
    { bursts: game.bursts, fps: GTK.current_framerate.round, boot_ms: game.boot_ms }.merge(performance)
  end

  # autopilot: bursts go off by themselves around the model
  def self.setup(name)
    case name
    when :autopilot then Game.current.autopilot = true
    else raise "Unknown setup #{name}"
    end
  end
end
