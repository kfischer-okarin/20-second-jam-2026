# Plays the sound effects in sounds/ (see scripts/generate-sounds) on a ring of audio channels.
# Missing files are skipped, so the game also runs without them.
class Sfx
  CHANNELS = 24

  # names are the sounds the game plays, each from sounds/<name>.wav
  def initialize(names)
    @available = names.select { |name| GTK.stat_file(path(name)) }
    @next_channel = 0
  end

  def play(audio, name, gain: 1.0, pitch: 1.0)
    return unless @available.include?(name)

    @next_channel = (@next_channel + 1) % CHANNELS
    audio[:"sfx_#{@next_channel}"] = { input: path(name), gain: gain, pitch: pitch }
  end

  # Keeps a looping sound playing from the first call on, at the gain of the latest call
  def play_loop(audio, name, gain)
    return unless @available.include?(name)

    audio[name] ||= { input: path(name), looping: true, gain: 0.0 }
    audio[name][:gain] = gain
  end

  private

  def path(name)
    "sounds/#{name}.wav"
  end
end
