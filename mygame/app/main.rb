require 'shaders/bright_pass.frag.hlsl'
require 'shaders/post.frag.hlsl'
require 'shaders/coffee.frag.hlsl'
require 'shaders/shadow.frag.hlsl'
require 'shaders/afterimage.frag.hlsl'

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
require 'app/render/layer_sprite'
require 'app/render/triangle_batch'
require 'app/sfx'
require 'app/latte/view'
require 'app/latte/cup'
require 'app/latte/pitcher'
require 'app/latte/models'
require 'app/latte/coffee_surface'
require 'app/latte/shadows'
require 'app/latte/spills'
require 'app/latte/table'
require 'app/latte/world'
require 'app/latte/steam'
require 'app/latte/terrace'
require 'app/latte/ending_models'
require 'app/latte/ending'
require 'app/latte/autopilot'
require 'app/game'
require 'app/game_cli'

module Main
  # Files whose changes can change how a baked model looks
  SHAPE_FILES = %w[render/sdf.rb render/sdf_baker.rb render/splat_model.rb render/noise3.rb render/rng.rb
                   latte/models.rb latte/cup.rb latte/pitcher.rb latte/ending_models.rb].freeze

  def start
    Game.current = Game.new(args)
  end

  def tick
    restart_with_new_code if game_code_reloaded?
    Game.current.tick(args)
    Game.current.post.cycle_debug_view if inputs.keyboard.key_down.f1
  end

  # Objects built by older code lack whatever new code expects of them (an instance variable added to an
  # initialize is nil on them), so the game starts over whenever hot reload changed its code. Baking takes
  # seconds, so models are baked again only when code that shapes them changed. main.rb restarts through
  # DR.reset below anyway.
  def restart_with_new_code
    ModelCache.clear if $gtk.files_reloaded.any? { |file| SHAPE_FILES.any? { |shape| file.end_with?(shape) } }
    Game.current = Game.new(args)
  end

  def game_code_reloaded?
    $gtk.files_reloaded.any? { |file| file.end_with?('.rb') && !file.end_with?('main.rb') }
  end
end

DR.reset
