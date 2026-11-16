# The Ruby half of the web runtime: the part of DragonRuby's API that mygame uses, built on WebHost (main.c) and
# host.js. Whatever else a game calls raises a NotImplementedError that names it, so a change made in DragonRuby
# that needs more of the engine says what to add here (see web/README.md).

class LoadError < ScriptError; end unless Object.const_defined?(:LoadError)

module Kernel
  def puts(*lines)
    lines = [''] if lines.empty?
    lines.flatten.each do |line|
      text = line.to_s
      print(text.end_with?("\n") ? text : "#{text}\n")
    end
    nil
  end

  def require(path)
    WebRuntime.instance.require(path)
  end

  def self.tick_count
    WebRuntime.instance.tick_count
  end

  def self.global_tick_count
    WebRuntime.instance.tick_count
  end
end

class Integer
  def idiv(other)
    other.is_a?(Integer) ? div(other) : (self / other).floor
  end
end

class Float
  def idiv(other)
    (self / other).floor
  end
end

module GTK
  extend self

  def stat_file(path)
    WebHost.file_exist?(path) ? { path: path, file_type: :regular } : nil
  end

  def read_file(path)
    WebHost.read_file(path)
  end

  def current_framerate
    WebHost.framerate
  end

  # Hot reload exists only in DragonRuby
  def files_reloaded
    []
  end

  def reset(*)
    nil
  end

  def platform
    'Emscripten'
  end

  def platform?(name)
    %i[web emscripten].include?(name.to_sym)
  end

  def production?
    true
  end

  def method_missing(name, *)
    WebRuntime.not_implemented("GTK.#{name}")
  end

  def respond_to_missing?(*)
    false
  end
end

DR = GTK unless Object.const_defined?(:DR)
$gtk = GTK

# --- The runtime ---------------------------------------------------------------------------------------------

# Loads the game, runs its ticks and turns what a tick put into args.outputs and args.audio into WebHost calls
class WebRuntime
  attr_reader :args, :tick_count

  class << self
    attr_accessor :instance

    def not_implemented(what)
      raise NotImplementedError, "#{what} is not implemented by the web runtime yet (see web/README.md)"
    end
  end

  def initialize
    WebRuntime.instance = self
    @tick_count = 0
    @loaded = {}
    @texture_ids = {}
    @pixel_arrays = {}
    @render_target_sizes = {}
    @args = Args.new(self)
    $args = @args # rubocop:disable Style/GlobalVars
    @ffi = WebHost::FFI.new
    @audio = AudioSync.new
    WebHost.default_scale_quality = metadata.fetch('scale_quality', '0').to_i
  end

  def boot
    require 'app/main'
    @main = MainRunner.new(@args)
  end

  def tick
    @args.begin_tick(WebHost.input)
    @main.start if @tick_count.zero?
    @main.tick
    render(@args.outputs)
    @audio.sync(@args.audio)
    @tick_count += 1
  end

  # Answers like Kernel#require: false when the file was already loaded
  def require(path)
    file = path.end_with?('.rb') || path.end_with?('.hlsl') ? path : "#{path}.rb"
    return false if @loaded[file]
    raise LoadError, "cannot load such file -- #{path}" unless WebHost.file_exist?(file)

    @loaded[file] = true
    # Shaders are compiled to WebGL by web/build; requiring one only checks that it was
    WebHost.load(file) unless file.end_with?('.hlsl')
    true
  end

  # Ids of the textures that sprites name with path: render targets, pixel arrays and image files
  def texture_id(path)
    name = path.to_s
    @texture_ids[name] ||= begin
      id = @texture_ids.length + 1
      WebHost.register_texture(id, name)
      id
    end
  end

  def pixel_array(name)
    array = @pixel_arrays[name.to_s] ||= PixelArray.new
    array.touched = true
    array
  end

  def render_target_size(name)
    @render_target_sizes[name] || [1280, 720]
  end

  def remember_render_target_size(name, w, h)
    @render_target_sizes[name] = [w, h]
  end

  def evaluate(code)
    TOPLEVEL_BINDING_RECEIVER.instance_eval(code)
  end

  def describe_exception(exception)
    backtrace = exception.backtrace || []
    (["#{exception.class}: #{exception.message}"] + backtrace.map { |line| "  #{line}" }).join("\n")
  end

  private

  def metadata
    text = WebHost.read_file('metadata/game_metadata.txt') || ''
    text.lines.each_with_object({}) do |line, values|
      key, value = line.strip.split('=', 2)
      values[key] = value if value && !key.start_with?('#')
    end
  end

  # Like DragonRuby: pixel arrays that were touched, then render targets in the order the tick first touched them,
  # then the screen
  def render(outputs)
    @pixel_arrays.each do |name, array|
      next unless array.touched

      WebHost.upload_pixels(texture_id(name), array.w, array.h, array.pixels || [])
      array.touched = false
    end
    outputs.touched_targets.each do |target|
      render_target(target)
    end
    WebHost.begin_screen(*rgba(outputs.background_color))
    draw_collections(outputs)
  end

  def render_target(target)
    remember_render_target_size(target.name, target.w, target.h)
    WebHost.begin_target(texture_id(target.name), target.w.to_i, target.h.to_i, *rgba(target.background_color))
    draw_collections(target)
    attach_shader(target, target.shader) if target.shader
  end

  def draw_collections(outputs)
    outputs.each_collection do |primitives|
      draw_all(primitives)
    end
  end

  # Like DragonRuby, a render target's shader does not change the target: it is the fragment shader that draws the
  # target wherever a sprite shows it, with the target as t0 and the sprite's texture coordinate and color
  def attach_shader(target, shader)
    uniforms = (shader[:uniforms] || []).flat_map { |uniform| [uniform[:type] == :int ? 1 : 0, uniform[:value]] }
    textures = (shader[:textures] || []).map { |texture| texture_id(texture) }
    WebHost.set_shader(texture_id(target.name), WebHost.shader_id(shader[:path].to_s), textures, uniforms)
  end

  def rgba(color)
    r, g, b, a = color
    [r.to_i, g.to_i, b.to_i, (a || 255).to_i]
  end

  def draw_all(primitives)
    primitives.each do |primitive|
      draw(primitive)
    end
  end

  def draw(primitive)
    case primitive
    when nil then nil
    when Array then draw_all(primitive)
    when Hash then draw_hash(primitive)
    else draw_object(primitive)
    end
  end

  def draw_hash(hash)
    case hash[:primitive_marker] || inferred_marker(hash)
    when :sprite then draw_sprite_hash(hash)
    when :solid then draw_sprite_hash(hash.merge(path: :pixel))
    else WebRuntime.not_implemented("Drawing #{hash.inspect}")
    end
  end

  def inferred_marker(hash)
    return :sprite if hash.key?(:path)
    return :label if hash.key?(:text)
    return :line if hash.key?(:x2) && !hash.key?(:w)

    :solid
  end

  # rubocop:disable-next Metrics/AbcSize
  def draw_sprite_hash(sprite)
    @ffi.draw_sprite_6 sprite[:x], sprite[:y], sprite[:w], sprite[:h], (sprite[:path] || 'pixel').to_s,
                       sprite[:angle], sprite[:a], sprite[:r], sprite[:g], sprite[:b],
                       sprite[:tile_x], sprite[:tile_y], sprite[:tile_w], sprite[:tile_h],
                       sprite[:flip_horizontally], sprite[:flip_vertically],
                       sprite[:angle_anchor_x], sprite[:angle_anchor_y],
                       sprite[:source_x], sprite[:source_y], sprite[:source_w], sprite[:source_h],
                       sprite[:blendmode_enum], sprite[:anchor_x], sprite[:anchor_y], sprite[:scale_quality_enum]
  end

  def draw_object(object)
    marker = object.respond_to?(:primitive_marker) ? object.primitive_marker : nil
    return object.draw_override(@ffi) if object.respond_to?(:draw_override)
    return draw_sprite_hash(SpriteAttributes.new(object)) if marker == :sprite

    WebRuntime.not_implemented("Drawing #{object.class} (#{marker.inspect})")
  end
end

TOPLEVEL_BINDING_RECEIVER = self

# Reads sprite attributes from an object the way a Hash would give them
class SpriteAttributes
  def initialize(object)
    @object = object
  end

  def [](name)
    @object.respond_to?(name) ? @object.send(name) : nil
  end
end

# Calls into the game the way DragonRuby does: through module Main (with args, inputs, outputs, state and audio
# available as methods), or through top-level tick(args) and boot(args)
class MainRunner
  def initialize(args)
    @args = args
    if Object.const_defined?(:Main)
      @receiver = Object.new
      @receiver.extend(MainHelpers)
      @receiver.extend(Object.const_get(:Main))
      @receiver.instance_variable_set(:@args, args)
      @receiver.boot if @receiver.respond_to?(:boot)
    else
      @receiver = TOPLEVEL_BINDING_RECEIVER
      @receiver.send(:boot, args) if @receiver.respond_to?(:boot, true)
    end
  end

  def start
    return unless @receiver.respond_to?(:start, true)

    main_module? ? @receiver.start : @receiver.send(:start, @args)
  end

  def tick
    main_module? ? @receiver.tick : @receiver.send(:tick, @args)
  end

  private

  def main_module?
    @receiver.is_a?(MainHelpers)
  end
end

module MainHelpers
  attr_reader :args

  %i[inputs outputs state audio gtk grid events].each do |name|
    define_method(name) { @args.send(name) }
  end
end

# --- args ------------------------------------------------------------------------------------------------------

class Args
  attr_reader :inputs, :outputs, :audio, :state, :grid

  def initialize(runtime)
    @runtime = runtime
    @inputs = Inputs.new
    @audio = {}
    @state = State.new
    @grid = Grid.new
  end

  def begin_tick(input_snapshot)
    @inputs.update(input_snapshot)
    @outputs = Outputs.new(@runtime)
  end

  def pixel_array(name)
    @runtime.pixel_array(name)
  end

  def render_target(name)
    @outputs[name]
  end

  def gtk
    GTK
  end

  def events
    WebRuntime.not_implemented('args.events')
  end

  def tick_count
    Kernel.tick_count
  end

  def method_missing(name, *)
    WebRuntime.not_implemented("args.#{name}")
  end

  def respond_to_missing?(*)
    false
  end
end

class Grid
  def w
    1280
  end

  def h
    720
  end

  def method_missing(name, *)
    WebRuntime.not_implemented("args.grid.#{name}")
  end

  def respond_to_missing?(*)
    false
  end
end

# args.state: attributes made up on the spot, nil until set
class State
  def initialize
    @values = {}
  end

  def method_missing(name, *arguments)
    key = name.to_s
    return @values[key.chomp('=').to_sym] = arguments.first if key.end_with?('=')

    @values[name]
  end

  def respond_to_missing?(*)
    true
  end
end

class PixelArray
  attr_accessor :w, :h, :pixels, :touched

  def initialize
    @w = 0
    @h = 0
    @pixels = []
  end
end

# --- Outputs ---------------------------------------------------------------------------------------------------

# Primitive collections that the web runtime cannot draw yet fail as soon as something is put into them
class UnsupportedPrimitives
  def initialize(name)
    @name = name
  end

  def <<(_primitive)
    WebRuntime.not_implemented(@name)
  end
  alias push <<
  alias concat <<

  def each; end
end

module PrimitiveCollections
  attr_reader :sprites, :primitives
  attr_accessor :background_color

  UNSUPPORTED = %i[solids labels lines borders static_sprites static_primitives static_solids static_labels
                   static_lines static_borders].freeze

  UNSUPPORTED.each do |name|
    define_method(name) { UnsupportedPrimitives.new("#{name} in #{description}") }
  end

  def each_collection
    yield @sprites
    yield @primitives
  end

  private

  def initialize_collections(background_color)
    @sprites = []
    @primitives = []
    @background_color = background_color
  end
end

class Outputs
  include PrimitiveCollections

  def initialize(runtime)
    @runtime = runtime
    @targets = {}
    initialize_collections([230, 230, 230, 255])
  end

  def [](name)
    name = name.to_s
    if %w[pixel solid].include?(name)
      raise ArgumentError, "The render target name #{name} is reserved by DragonRuby; use another name."
    end

    @targets[name] ||= RenderTarget.new(name, *@runtime.render_target_size(name))
  end

  # In the order they were first touched
  def touched_targets
    @targets.values
  end

  def shader=(_shader)
    WebRuntime.not_implemented('A shader on the screen (outputs.shader)')
  end

  def debug
    WebRuntime.not_implemented('outputs.debug')
  end

  def description
    'outputs'
  end
end

class RenderTarget
  include PrimitiveCollections

  attr_reader :name
  attr_accessor :w, :h, :shader, :transient, :clear_before_render

  def initialize(name, w, h)
    @name = name
    @w = w
    @h = h
    @clear_before_render = true
    initialize_collections([255, 255, 255, 0])
  end

  def set(w: nil, h: nil, background_color: nil)
    @w = w if w
    @h = h if h
    @background_color = background_color if background_color
    self
  end

  def width
    @w
  end

  def height
    @h
  end

  def transient!
    @transient = true
    self
  end

  def description
    "outputs[:#{@name}]"
  end
end

# --- Inputs ----------------------------------------------------------------------------------------------------

# key_down, key_held or key_up of a keyboard or controller: answers true for the keys in that state, nil otherwise
class KeyState
  def initialize
    @keys = {}
  end

  def replace(names)
    @keys.clear
    names.each do |name|
      @keys[name.to_sym] = true
    end
  end

  def truthy_keys
    @keys.keys
  end

  def method_missing(name, *)
    @keys[name]
  end

  def respond_to_missing?(*)
    true
  end
end

# Directions the way DragonRuby combines them: when both opposite directions are held, the one of the previous
# tick wins
module Directions
  def left_right
    directional_vector&.first || 0
  end

  def up_down
    directional_vector&.last || 0
  end

  def directional_vector
    @directional_vector
  end

  def last_directional_vector
    @last_directional_vector
  end

  private

  def update_directions
    @last_directional_vector = @directional_vector
    last_x, last_y = @last_directional_vector || [0, 0]
    x = axis(left, right, last_x)
    y = axis(down, up, last_y)
    @directional_vector = x.zero? && y.zero? ? nil : [x, y]
  end

  def axis(negative, positive, last)
    return last if negative && positive && !last.zero?
    return -1 if negative
    return 1 if positive

    0
  end
end

class Keyboard
  include Directions

  attr_reader :key_down, :key_held, :key_up

  def initialize
    @key_down = KeyState.new
    @key_held = KeyState.new
    @key_up = KeyState.new
  end

  def update(down_keys, held_keys, up_keys)
    @key_down.replace(down_keys)
    @key_held.replace(held_keys)
    @key_up.replace(up_keys)
    update_directions
  end

  def left
    key?(:left) || key?(:a_scancode)
  end

  def right
    key?(:right) || key?(:d_scancode)
  end

  def up
    key?(:up) || key?(:w_scancode)
  end

  def down
    key?(:down) || key?(:s_scancode)
  end

  def method_missing(name, *)
    key?(name)
  end

  def respond_to_missing?(*)
    true
  end

  private

  def key?(name)
    @key_down.send(name) || @key_held.send(name) || nil
  end
end

class Controller
  include Directions

  attr_reader :key_down, :key_held, :key_up, :connected, :left_analog_x_perc, :left_analog_y_perc,
              :right_analog_x_perc, :right_analog_y_perc

  def initialize
    @key_down = KeyState.new
    @key_held = KeyState.new
    @key_up = KeyState.new
    @connected = false
    @left_analog_x_perc = @left_analog_y_perc = @right_analog_x_perc = @right_analog_y_perc = 0.0
  end

  def update(down_keys, held_keys, up_keys, analog)
    @key_down.replace(down_keys)
    @key_held.replace(held_keys)
    @key_up.replace(up_keys)
    @connected = !analog.empty?
    @left_analog_x_perc, @left_analog_y_perc, @right_analog_x_perc, @right_analog_y_perc = analog.map(&:to_f)
    update_directions
  end

  %i[left right up down].each do |direction|
    define_method(direction) { @key_down.send(direction) || @key_held.send(direction) || nil }
  end

  def method_missing(name, *)
    @key_down.send(name) || @key_held.send(name) || nil
  end

  def respond_to_missing?(*)
    true
  end
end

# A mouse button press or release, with where it happened
class MouseEvent
  attr_reader :x, :y, :created_at

  def initialize(x, y)
    @x = x
    @y = y
    @created_at = Kernel.tick_count
  end

  def point
    { x: @x, y: @y }
  end
end

class Mouse
  attr_reader :x, :y, :moved, :button_left, :button_middle, :button_right, :click, :up, :wheel

  def initialize
    @x = 0
    @y = 0
  end

  # x, y, moved, left button pressed, held and released, middle and right button held, as 0 or 1
  def update(values)
    @x, @y, moved, left_down, left_held, left_up, middle_held, right_held = values.map(&:to_i)
    @moved = moved == 1 || nil
    @button_left = left_held == 1
    @button_middle = middle_held == 1
    @button_right = right_held == 1
    @click = event_if(left_down)
    @up = event_if(left_up)
  end

  def down
    @click
  end

  def held
    @button_left && !@click
  end

  def point
    { x: @x, y: @y }
  end
  alias position point

  def inside_rect?(rect)
    rect_x, rect_y, rect_w, rect_h = rect.is_a?(Hash) ? rect.values_at(:x, :y, :w, :h) : rect
    @x >= rect_x && @x < rect_x + rect_w && @y >= rect_y && @y < rect_y + rect_h
  end

  def method_missing(name, *)
    WebRuntime.not_implemented("inputs.mouse.#{name}")
  end

  def respond_to_missing?(*)
    false
  end

  private

  def event_if(flag)
    flag == 1 ? MouseEvent.new(@x, @y) : nil
  end
end

class Inputs
  attr_reader :keyboard, :mouse, :controller_one, :controller_two, :controller_three, :controller_four

  def initialize
    @keyboard = Keyboard.new
    @mouse = Mouse.new
    @controller_one = Controller.new
    @controller_two = Controller.new
    @controller_three = Controller.new
    @controller_four = Controller.new
  end

  def controllers
    [@controller_one, @controller_two, @controller_three, @controller_four]
  end

  # One line per device and state, as host.js writes them: "kd space z", "m 640 360 1 0 0 0 0 0", ...
  def update(snapshot)
    lines = snapshot.split("\n").to_h { |line|
      kind, *values = line.split
      [kind, values]
    }
    lines.default = []
    @keyboard.update(lines['kd'], lines['kh'], lines['ku'])
    @mouse.update(lines['m'])
    @controller_one.update(lines['cd'], lines['ch'], lines['cu'], lines['ca'])
  end

  def up
    @keyboard.up || @controller_one.up
  end

  def down
    @keyboard.down || @controller_one.down
  end

  def left
    @keyboard.left || @controller_one.left
  end

  def right
    @keyboard.right || @controller_one.right
  end

  def directional_vector
    @keyboard.directional_vector || @controller_one.directional_vector
  end

  def left_right
    directional_vector&.first || 0
  end

  def up_down
    directional_vector&.last || 0
  end

  def click
    @mouse.click
  end

  def method_missing(name, *)
    WebRuntime.not_implemented("inputs.#{name}")
  end

  def respond_to_missing?(*)
    false
  end
end

# --- Audio -----------------------------------------------------------------------------------------------------

# Plays what args.audio holds: a new Hash under a key starts a sound, changing its gain, pitch or paused changes the
# playing sound, removing it stops it, and a finished sound is removed (like DragonRuby)
class AudioSync
  Voice = Struct.new(:id, :sound, :gain, :pitch, :paused)

  def initialize
    @voices = {}
    @next_id = 0
  end

  def sync(audio)
    remove_finished(audio)
    @voices.each_key do |key|
      stop(key) unless audio[key].equal?(@voices[key].sound)
    end
    audio.each do |key, sound|
      next unless sound

      voice = @voices[key]
      voice ? update(voice, sound) : play(key, sound)
    end
  end

  private

  def remove_finished(audio)
    finished = WebHost.audio_finished.split.map(&:to_i)
    return if finished.empty?

    @voices.dup.each do |key, voice|
      next unless finished.include?(voice.id)

      @voices.delete(key)
      audio.delete(key) if audio[key].equal?(voice.sound)
    end
  end

  def stop(key)
    WebHost.audio_stop(@voices.delete(key).id)
  end

  def play(key, sound)
    raise ArgumentError, "args.audio[#{key.inspect}] must be a Hash, got #{sound.inspect}" unless sound.is_a?(Hash)

    @next_id += 1
    voice = Voice.new(@next_id, sound, gain(sound), pitch(sound), paused?(sound))
    @voices[key] = voice
    WebHost.audio_play(voice.id, sound[:input].to_s, voice.gain, voice.pitch, sound[:looping])
    WebHost.audio_update(voice.id, voice.gain, voice.pitch, true) if voice.paused
  end

  def update(voice, sound)
    gain = gain(sound)
    pitch = pitch(sound)
    paused = paused?(sound)
    return if gain == voice.gain && pitch == voice.pitch && paused == voice.paused

    voice.gain = gain
    voice.pitch = pitch
    voice.paused = paused
    WebHost.audio_update(voice.id, gain, pitch, paused)
  end

  def gain(sound)
    (sound[:gain] || 1.0).to_f
  end

  def pitch(sound)
    (sound[:pitch] || 1.0).to_f
  end

  def paused?(sound)
    sound[:paused] ? true : false
  end
end
