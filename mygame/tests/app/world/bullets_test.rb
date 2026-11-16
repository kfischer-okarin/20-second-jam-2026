require 'tests/test_helper'

describe Bullets do
  subject { Bullets.new }
  let(:invader) { { x: 20.0, y: 0.0, radius: 5.0 } }

  test 'a bullet that reaches an invader hits it and is gone' do
    subject.fire(0.0, 0.0, 1.0, 0.0)
    subject.update(0.06)
    hits = []
    subject.collide([invader]) do |target, _bullet|
      hits << target
    end
    assert.equal! [hits, subject.list], [[invader], []]
  end

  test 'a bullet that passes by keeps flying' do
    subject.fire(0.0, 10.0, 1.0, 0.0)
    subject.update(0.08)
    hits = []
    subject.collide([invader]) do |target, _bullet|
      hits << target
    end
    assert.equal! [hits, subject.list.length], [[], 1]
  end

  test 'bullets burn out after their life' do
    subject.fire(0.0, 0.0, 0.0, 0.0)
    subject.update(Bullets::LIFE + 0.01)
    assert.empty! subject.list
  end
end
