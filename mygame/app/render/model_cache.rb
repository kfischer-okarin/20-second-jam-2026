# Baked models, kept from game to game because baking them takes about a second. Main empties it whenever hot
# reload changes game code, since almost any file (an SDF primitive, the baker, a model's parts) can change how
# a model looks.
module ModelCache
  @models = {}

  def self.fetch(key, &bake)
    @models[key] ||= bake.call
  end

  def self.clear
    @models.clear
  end
end
