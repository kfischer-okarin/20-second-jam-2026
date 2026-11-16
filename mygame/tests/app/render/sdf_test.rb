require 'tests/test_helper'

describe Sdf do
  test 'sphere is negative inside, zero on the surface and positive outside' do
    assert.equal! Sdf.sphere(0.0, 0.0, 1.0, 2.0), -1.0
    assert.equal! Sdf.sphere(2.0, 0.0, 0.0, 2.0), 0.0
    assert.equal! Sdf.sphere(0.0, 3.0, 0.0, 2.0), 1.0
  end

  test 'round box measures from its rounded faces' do
    assert.equal! Sdf.round_box(3.0, 0.0, 0.0, 2.0, 1.0, 1.0, 0.5), 1.0
    assert.equal! Sdf.round_box(0.0, 0.0, 0.0, 2.0, 1.0, 1.0, 0.5), -1.0
  end

  test 'smooth union bulges below the plain minimum where two shapes meet' do
    assert.true! Sdf.smooth_union(0.5, 0.5, 1.0) < 0.5
    assert.equal! Sdf.smooth_union(0.0, 5.0, 1.0), 0.0
  end

  test 'smooth subtract carves the second shape out of the first' do
    assert.equal! Sdf.smooth_subtract(-1.0, -2.0, 0.0), 2.0
    assert.equal! Sdf.smooth_subtract(-1.0, 3.0, 0.0), -1.0
  end
end
