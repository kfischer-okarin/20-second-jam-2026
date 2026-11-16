require 'tests/test_helper'

describe Rng do
  test 'at depends only on its arguments' do
    assert.equal! Rng.at(11, 5, :size), Rng.at(11, 5, :size)
  end

  test 'at gives every channel, index and seed its own numbers' do
    values = [Rng.at(11, 5, :size), Rng.at(11, 5, :tint), Rng.at(11, 6, :size), Rng.at(12, 5, :size)]
    assert.equal! values.uniq.length, 4
  end

  test 'at spreads evenly over 0..1' do
    values = Array.new(2000) { |i| Rng.at(3, i, :spread) }
    low, high = values.minmax
    mean = values.sum / values.length
    assert.equal! [low >= 0.0, high <= 1.0, (mean - 0.5).abs < 0.02], [true, true, true]
  end
end
