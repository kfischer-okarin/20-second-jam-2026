# Bakes that take seconds, kept in files between runs of the game (in tmp/bakes, which is not in the repository),
# and baked again when the code that shapes them changed: each file starts with a checksum of the contents of
# the source files it was baked from, and of salt (what else it depends on, as a String).
#
# A bake is a Hash of names to Hashes of fields, each an Array of numbers: Floats, or Integers for the fields
# named in integers.
module BakeFiles
  DIRECTORY = 'tmp/bakes'.freeze

  extend self

  def fetch(name, sources, salt: '', integers: [])
    key = checksum(sources, salt).to_s
    path = "#{DIRECTORY}/#{name}.txt"
    stored = read(path, key, integers)
    return stored if stored

    bake = yield
    $gtk.write_file(path, serialize(key, bake))
    bake
  end

  private

  def checksum(sources, salt)
    hash = 5381
    [*sources.map { |source| $gtk.read_file(source) || '' }, salt].each do |text|
      text.each_byte do |byte|
        hash = ((hash * 33) + byte) & 0x7fff_ffff
      end
    end
    hash
  end

  # One line for the checksum, then one for every field: its name's, its field's, then its numbers
  def serialize(key, bake)
    lines = [key]
    bake.each do |name, fields|
      fields.each do |field, values|
        lines << "#{name} #{field} #{values.join(' ')}"
      end
    end
    lines.join("\n")
  end

  def read(path, key, integers)
    lines = ($gtk.read_file(path) || '').split("\n")
    return nil unless lines.shift == key

    bake = {}
    lines.each do |line|
      name, field, values = parse(line, integers)
      (bake[name] ||= {})[field] = values
    end
    bake
  end

  def parse(line, integers)
    name, field, *values = line.split
    field = field.to_sym
    [name.to_sym, field, integers.include?(field) ? values.map(&:to_i) : values.map(&:to_f)]
  end
end
