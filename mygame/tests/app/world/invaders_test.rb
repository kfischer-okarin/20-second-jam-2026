require 'tests/test_helper'

# A planet in the middle of the screen, without baking one
StillPlanet = Struct.new(:x, :y, :radius)

describe Invaders do
  subject { Invaders.new(StillPlanet.new(160.0, 90.0, 44.0)) }

  define_helper :splats_in do |layer|
    subject.batches.find { |batch| batch.layer == layer }.count
  end

  test 'every type has the required settings and a baked model' do
    incomplete = Invaders::TYPES.reject { |type, info|
      %i[parts bake radius scale hp score speed].all? { |key| info.key?(key) } && !Invaders.models[type].px.empty?
    }
    assert.empty! incomplete.keys
  end

  test 'every type can fly, be drawn and fall apart' do
    broken = Invaders::TYPES.keys.reject { |type|
      invader = subject.spawn(type, 1.0, 120.0)
      subject.update(0.5)
      subject.splat_cloud(invader).any? && invader[:blast].positive? &&
        Effects::RAMPS.key?(invader[:debris_glow])
    }
    subject.render(Lighting.new)
    # each of them drew dozens of splats
    assert.equal! [broken, splats_in(:solid) > 50 * Invaders::TYPES.length], [[], true]
  end

  test 'an invader is drawn into the layer of its kind' do
    subject.spawn(:drone, 1.0, 120.0)[:layer] = :glow
    subject.render(Lighting.new)
    assert.equal! [splats_in(:solid), splats_in(:glow) > 50], [0, true]
  end

  test 'invaders that reach the surface land and leave the list' do
    subject.spawn(:drone, 0.0, 46.0)
    assert.equal! [subject.update(0.1).length, subject.list.length], [1, 0]
  end
end
