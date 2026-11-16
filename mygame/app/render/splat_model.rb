# A cloud of oriented surface splats stored as parallel arrays, which keeps the per-frame loops fast in mruby.
class SplatModel
  attr_reader :count, :px, :py, :pz, :nx, :ny, :nz, :cr, :cg, :cb, :em, :size, :group, :aux

  def initialize
    @px = []
    @py = []
    @pz = []
    @nx = []
    @ny = []
    @nz = []
    @cr = []
    @cg = []
    @cb = []
    @em = []
    @size = []
    @group = []
    @aux = []
    @count = 0
  end

  # rubocop:disable-next Metrics/ParameterLists
  def add(x, y, z, nx, ny, nz, r, g, b, emission, size, group = 0, aux = 0.0)
    @px << x
    @py << y
    @pz << z
    @nx << nx
    @ny << ny
    @nz << nz
    @cr << r
    @cg << g
    @cb << b
    @em << emission
    @size << size
    @group << group
    @aux << aux
    @count += 1
  end

  def bounding_radius
    @bounding_radius ||= (0...@count).map { |i| Math.sqrt((@px[i]**2) + (@py[i]**2) + (@pz[i]**2)) }.max || 0.0
  end
end
