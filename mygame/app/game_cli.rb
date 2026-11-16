# Hooks for scripts/game (see README.md)
module GameCli
  def self.state
    game = Game.current
    performance = game.performance.map { |key, value| [key, value.round(2)] }.to_h
    { doom: game.doom.round(2), fps: GTK.current_framerate.round, boot_ms: game.boot_ms }.merge(performance)
  end
end
