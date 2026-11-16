require 'shaders/bright_pass.frag.hlsl'
require 'shaders/post.frag.hlsl'

require 'app/render/rot3'
require 'app/render/rng'
require 'app/render/noise3'
require 'app/render/sdf'
require 'app/render/splat_model'
require 'app/render/sdf_baker'
require 'app/render/model_cache'
require 'app/render/splat_batch'
require 'app/render/lighting'
require 'app/render/splat_renderer'
require 'app/render/pixel_font'
require 'app/render/textures'
require 'app/render/camera'
require 'app/render/post_process'
require 'app/render/frame_stats'
require 'app/render/particles'
require 'app/sfx'
require 'app/world/background'
require 'app/world/planet_baker'
require 'app/world/planet'
require 'app/game'
require 'app/game_cli'

module Main
  def start
    Game.current = Game.new(args)
  end

  def tick
    restart_with_new_code if game_code_reloaded?
    Game.current.tick(args)
    Game.current.post.cycle_debug_view if inputs.keyboard.key_down.f1
  end

  # Objects built by older code lack whatever new code expects of them (an instance variable added to an
  # initialize is nil on them), and baked models may look different now, so the game starts over with freshly
  # baked models whenever hot reload changed its code. main.rb restarts through DR.reset below anyway.
  def restart_with_new_code
    ModelCache.clear
    Game.current = Game.new(args)
  end

  def game_code_reloaded?
    $gtk.files_reloaded.any? { |file| file.end_with?('.rb') && !file.end_with?('main.rb') }
  end
end

DR.reset
