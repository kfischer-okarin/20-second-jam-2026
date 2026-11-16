require 'tests/test_helper'

describe Rot3 do
  define_helper :rounded do |vector|
    vector.map { |value| value.round(6) + 0.0 }
  end

  test 'rot_z turns x towards y' do
    assert.equal! rounded(Rot3.apply(Rot3.rot_z(Math::PI / 2), 1.0, 0.0, 0.0)), [0.0, 1.0, 0.0]
  end

  test 'rot_x tilts y towards the viewer' do
    assert.equal! rounded(Rot3.apply(Rot3.rot_x(Math::PI / 2), 0.0, 1.0, 0.0)), [0.0, 0.0, 1.0]
  end

  test 'mul applies the right matrix first' do
    m = Rot3.mul(Rot3.rot_z(Math::PI / 2), Rot3.rot_x(Math::PI / 2))
    assert.equal! rounded(Rot3.apply(m, 0.0, 1.0, 0.0)), [0.0, 0.0, 1.0]
    assert.equal! rounded(Rot3.apply(m, 1.0, 0.0, 0.0)), [0.0, 1.0, 0.0]
  end

  test 'axis_angle around z matches rot_z' do
    assert.equal! rounded(Rot3.axis_angle(0.0, 0.0, 1.0, 0.7)), rounded(Rot3.rot_z(0.7))
  end
end
