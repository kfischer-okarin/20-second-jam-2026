require 'tests/test_helper'

describe Particles do
  subject { Particles.new(:glow, ramps: { spark: [[255, 255, 255], [254, 190, 80], [0, 0, 0]] }) }

  test 'particles disappear once their life is over' do
    subject.spawn(0.0, 0.0, 10.0, 0.0, life: 0.5, size: 2.0, ramp: :spark)
    subject.update(0.3, 100.0, 100.0, 10.0)
    assert.equal! subject.count, 1
    subject.update(0.3, 100.0, 100.0, 10.0)
    assert.equal! subject.count, 0
  end

  test 'falling particles vanish when they reach the attractor' do
    subject.spawn(15.0, 0.0, -50.0, 0.0, life: 5.0, size: 2.0, color: [1, 2, 3], gravity: 10.0)
    subject.update(0.2, 0.0, 0.0, 10.0)
    assert.equal! subject.count, 0
  end

  test 'a negative attractor radius turns gravity off' do
    subject.spawn(15.0, 0.0, 0.0, 0.0, life: 5.0, size: 2.0, color: [1, 2, 3], gravity: 1000.0)
    subject.update(0.5, 0.0, 0.0, -1.0)
    assert.equal! subject.count, 1
    assert.equal! subject.render.data[0], 15.0
  end

  test 'additive particles fade to black along their ramp' do
    subject.spawn(0.0, 0.0, 0.0, 0.0, life: 1.0, size: 2.0, ramp: :spark)
    subject.update(0.999, 0.0, 0.0, -1.0)
    data = subject.render.data
    assert.equal! [data[5], data[6], data[7]], [0.0, 0.0, 0.0]
  end

  test 'solid particles cool towards the ember color' do
    particles = Particles.new(:solid, ember: [60.0, 30.0, 40.0])
    particles.spawn(0.0, 0.0, 0.0, 0.0, life: 1.0, size: 2.0, color: [200.0, 200.0, 200.0])
    particles.update(0.5, 0.0, 0.0, -1.0)
    data = particles.render.data
    assert.equal! [data[5], data[6], data[7]], [130.0, 115.0, 120.0]
  end
end
