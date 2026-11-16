require 'tests/test_helper'

describe SdfBaker do
  let(:spacing) { 0.8 }
  let(:model) do
    SdfBaker.bake([{ sdf: ->(x, y, z) { Sdf.sphere(x, y, z, 3.0) }, color: [100, 100, 100] }],
                  bounds: [-4, -4, -4, 4, 4, 4], spacing: spacing, size: 2.0, seed: 1)
  end
  let(:splats) { (0...model.count).to_a }

  define_helper :distance_to do |i, x, y, z|
    Math.sqrt(((model.px[i] - x)**2) + ((model.py[i] - y)**2) + ((model.pz[i] - z)**2))
  end

  test 'puts every splat on the surface' do
    assert.empty!(splats.reject { |i| (distance_to(i, 0, 0, 0) - 3.0).abs < 0.05 })
  end

  test 'points the normals outwards' do
    assert.empty!(splats.reject { |i| distance_to(i, -model.nx[i], -model.ny[i], -model.nz[i]) > 3.99 })
  end

  test 'keeps splats at least the spacing apart' do
    too_close = splats.combination(2).select { |i, j| distance_to(i, model.px[j], model.py[j], model.pz[j]) < spacing }
    assert.empty! too_close
  end

  test 'leaves no gaps: every point of the surface has a splat within one spacing' do
    points = Array.new(60) { |i| Rot3.apply(Rot3.rot_y(i * 1.1), Math.sin(i * 0.37) * 3, Math.cos(i * 0.37) * 3, 0.0) }
    assert.empty!(points.reject { |x, y, z| splats.any? { |i| distance_to(i, x, y, z) < spacing } })
  end
end
