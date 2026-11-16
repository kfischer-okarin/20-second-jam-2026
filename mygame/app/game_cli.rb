# Hooks for scripts/game (see README.md)
module GameCli
  def self.state
    game = Game.current
    { fps: GTK.current_framerate.round, boot_ms: game.boot_ms }
  end
end
