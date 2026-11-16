# Signed distance functions (negative inside), see https://iquilezles.org/articles/distfunctions/
module Sdf
  extend self

  def sphere(x, y, z, radius)
    Math.sqrt((x * x) + (y * y) + (z * z)) - radius
  end

  def ellipsoid(x, y, z, rx, ry, rz)
    k0 = Math.sqrt(((x / rx)**2) + ((y / ry)**2) + ((z / rz)**2))
    k1 = Math.sqrt(((x / (rx * rx))**2) + ((y / (ry * ry))**2) + ((z / (rz * rz))**2))
    return -[rx, ry, rz].min if k1 < 1e-9

    k0 * (k0 - 1.0) / k1
  end

  def round_box(x, y, z, half_x, half_y, half_z, rounding)
    qx = x.abs - half_x + rounding
    qy = y.abs - half_y + rounding
    qz = z.abs - half_z + rounding
    outside = Math.sqrt(([qx, 0.0].max**2) + ([qy, 0.0].max**2) + ([qz, 0.0].max**2))
    inside = [[qx, qy, qz].max, 0.0].min
    outside + inside - rounding
  end

  def capsule(x, y, z, start, finish, radius)
    pax = x - start[0]
    pay = y - start[1]
    paz = z - start[2]
    bax = finish[0] - start[0]
    bay = finish[1] - start[1]
    baz = finish[2] - start[2]
    h = (((pax * bax) + (pay * bay) + (paz * baz)) / ((bax * bax) + (bay * bay) + (baz * baz))).clamp(0.0, 1.0)
    Math.sqrt(((pax - (bax * h))**2) + ((pay - (bay * h))**2) + ((paz - (baz * h))**2)) - radius
  end

  # Ring lying in the xz plane
  def torus(x, y, z, ring_radius, tube_radius)
    q = Math.sqrt((x * x) + (z * z)) - ring_radius
    Math.sqrt((q * q) + (y * y)) - tube_radius
  end

  # Cone pointing up along y with its base on y = 0
  def cone(x, y, z, radius, height)
    q = Math.sqrt((x * x) + (z * z))
    side = ((q * height) + (y * radius) - (radius * height)) / Math.sqrt((height * height) + (radius * radius))
    [side, -y, y - height].max
  end

  # smoothing is the distance over which the two shapes blend into each other
  def smooth_union(a, b, smoothing)
    return [a, b].min if smoothing <= 0

    h = (0.5 + (0.5 * (b - a) / smoothing)).clamp(0.0, 1.0)
    b + ((a - b) * h) - (smoothing * h * (1.0 - h))
  end

  # a with b cut away
  def smooth_subtract(a, b, smoothing)
    return [a, -b].max if smoothing <= 0

    h = (0.5 - (0.5 * (a + b) / smoothing)).clamp(0.0, 1.0)
    a + ((-b - a) * h) + (smoothing * h * (1.0 - h))
  end
end
