# How long frames take, for scripts/game state: update_ms (the tick), draw_ms and splats (the engine drawing the
# previous frame's splats, which happens after the tick), frame_ms (the time since the previous tick began) and
# peak_ms (the slowest recent update + draw, decaying)
class FrameStats
  attr_reader :values

  def initialize
    @values = { update_ms: 0.0, draw_ms: 0.0, splats: 0, frame_ms: 0.0, peak_ms: 0.0 }
  end

  # Measures the block as the tick
  def measure
    started = Time.now.to_f
    yield
    values = @values
    values[:update_ms] = (Time.now.to_f - started) * 1000
    values[:draw_ms], values[:splats] = SplatBatch.take_draw_stats
    values[:frame_ms] = @last_tick_started ? (started - @last_tick_started) * 1000 : 0.0
    values[:peak_ms] = [values[:peak_ms] * 0.995, values[:update_ms] + values[:draw_ms]].max
    @last_tick_started = started
  end
end
