# Points and the kill chain: kills less than COMBO_WINDOW seconds apart chain up, and every third link of the
# chain raises the multiplier. The best score survives from round to round.
class Scoring
  COMBO_WINDOW = 1.8
  MAX_MULTIPLIER = 6

  attr_reader :score, :combo, :max_combo, :kills, :best, :new_best

  def initialize
    @best = 0
    reset
  end

  def reset
    @score = 0
    @combo = 0
    @combo_timer = 0.0
    @max_combo = 0
    @kills = 0
    @new_best = false
  end

  def multiplier
    [1 + @combo.idiv(3), MAX_MULTIPLIER].min
  end

  # How much of the window for the next link is left (1.0 right after a kill)
  def combo_fraction
    (@combo_timer / COMBO_WINDOW).clamp(0.0, 1.0)
  end

  def update(dt)
    @combo_timer -= dt
    @combo = 0 if @combo_timer <= 0.0
  end

  # Adds the kill to the chain and returns what it is worth with the multiplier the chain reached
  def kill(base_points)
    @combo += 1
    @combo_timer = COMBO_WINDOW
    @max_combo = [@max_combo, @combo].max
    @kills += 1
    points = base_points * multiplier
    @score += points
    points
  end

  # Ends the chain and returns how long it was
  def break_chain
    length = @combo
    @combo = 0
    length
  end

  def finish_round
    @new_best = @score > @best
    @best = [@best, @score].max
  end
end
