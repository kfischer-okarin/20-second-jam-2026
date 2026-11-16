require 'tests/test_helper'

describe Scoring do
  subject { Scoring.new }

  test 'every third link of the chain raises the multiplier' do
    points = Array.new(7) { subject.kill(100) }
    assert.equal! points, [100, 100, 200, 200, 200, 300, 300]
    assert.equal! subject.score, 1400
  end

  test 'the multiplier stops at its maximum' do
    30.times do
      subject.kill(100)
    end
    assert.equal! subject.multiplier, Scoring::MAX_MULTIPLIER
  end

  test 'the chain ends when the window passes without a kill' do
    subject.kill(100)
    subject.update(Scoring::COMBO_WINDOW + 0.01)
    assert.equal! subject.combo, 0
    assert.equal! subject.max_combo, 1
  end

  test 'breaking the chain reports how long it was' do
    3.times do
      subject.kill(100)
    end
    assert.equal! subject.break_chain, 3
    assert.equal! subject.combo, 0
  end

  test 'the best score survives into the next round' do
    subject.kill(100)
    subject.finish_round
    subject.reset
    subject.finish_round
    assert.equal! [subject.best, subject.new_best], [100, false]
  end
end
