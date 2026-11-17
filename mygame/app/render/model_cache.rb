# Baked models, kept from game to game because baking them takes seconds. Main empties it whenever hot reload
# changes code that shapes models (an SDF primitive, the baker, a model's parts).
#
# Models needed later can be baked in the background: prepare queues them, and bake_some spends a few
# milliseconds of each frame on them inside a Fiber, which SdfBaker pauses at its checkpoints. fetch finishes a
# model right away if it is still needed before its turn.
module ModelCache
  @models = {}
  @bake_ms = {}
  @queue = []
  @fiber = nil
  @baking = nil
  @deadline = nil

  class << self
    # Milliseconds each model took to bake, with its number of splats
    attr_reader :bake_ms

    def fetch(key, &bake)
      return @models[key] if @models[key]

      finish_baking while @baking == key
      @queue.reject! do |queued, _bake|
        queued == key
      end
      @models[key] ||= timed(key, &bake)
    end

    def prepare(key, &bake)
      return if @models[key] || @baking == key || @queue.any? { |queued, _bake| queued == key }

      @queue << [key, bake]
    end

    # Bakes queued models for at most this many seconds
    def bake_some(seconds)
      return if @queue.empty? && !@fiber

      @fiber ||= Fiber.new { bake_queue }
      @deadline = Time.now.to_f + seconds
      @fiber.resume
      @deadline = nil
      @fiber = nil unless @fiber.alive?
    end

    # Called by SdfBaker between pieces of work: hands the frame back when its time is up. Only a background bake
    # has a deadline; one that is needed right away runs through.
    def checkpoint
      Fiber.yield if @deadline && Time.now.to_f > @deadline
    end

    def baking?
      !@queue.empty? || !@baking.nil?
    end

    def clear
      @models.clear
      @queue.clear
      @fiber = nil
      @baking = nil
      @deadline = nil
    end

    private

    def bake_queue
      until @queue.empty?
        key, bake = @queue.shift
        @baking = key
        @models[key] = timed(key, &bake)
        @baking = nil
      end
      @deadline = nil
    end

    def finish_baking
      @deadline = nil
      @fiber&.resume
      @fiber = nil unless @fiber&.alive?
    end

    def timed(key, &bake)
      started = Time.now.to_f
      model = bake.call
      @bake_ms[key] = [((Time.now.to_f - started) * 1000).round, model.count]
      model
    end
  end
end
