require 'tests/test_helper'

# Remembers the type and speed of every invader it is asked to spawn
class RecordingInvaders
  attr_reader :spawned

  def initialize
    @spawned = []
  end

  def spawn(type, _theta, _distance, speed_scale:)
    @spawned << [type, speed_scale]
  end
end

describe Spawner do
  let(:invaders) { RecordingInvaders.new }
  subject { Spawner.new(invaders) }

  test 'reports one plate for every plate moment that has passed' do
    assert.equal! subject.update(0.0, 11.0, 0.0).count(:plate), 2
  end

  test 'spawns a brute when its moment comes' do
    assert.includes! subject.update(0.0, 13.0, 0.0), :brute
    assert.equal! invaders.spawned.map(&:first), [:brute]
  end

  test 'a swarm is seven drones' do
    subject.skip_to(10.6)
    assert.equal! subject.update(0.0, 10.4, 0.0), [:swarm]
    assert.equal! invaders.spawned.map(&:first), [:drone] * 7
  end

  test 'skipping ahead forgets what would have been due earlier' do
    subject.skip_to(6.0)
    assert.empty! subject.update(0.0, 5.9, 0.0)
  end

  test 'the stream sends faster invaders as doom rises' do
    subject.update(1.0, 19.0, 0.5)
    assert.equal! invaders.spawned.map(&:last), [1.25]
  end
end
