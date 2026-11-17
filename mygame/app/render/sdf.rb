# Signed distance functions (negative inside), see https://iquilezles.org/articles/distfunctions/
# Baking evaluates them hundreds of thousands of times, so they compare with operators instead of [a, b].max
# (which allocates an array in mruby) and multiply instead of **.
# rubocop:disable-next Style/MinMaxComparison
module Sdf
  extend self

  def sphere(x, y, z, radius)
    Math.sqrt((x * x) + (y * y) + (z * z)) - radius
  end

  def ellipsoid(x, y, z, rx, ry, rz)
    ax = x / rx
    ay = y / ry
    az = z / rz
    k0 = Math.sqrt((ax * ax) + (ay * ay) + (az * az))
    bx = ax / rx
    by = ay / ry
    bz = az / rz
    k1 = Math.sqrt((bx * bx) + (by * by) + (bz * bz))
    if k1 < 1e-9
      smallest = rx < ry ? rx : ry
      return -(smallest < rz ? smallest : rz)
    end

    k0 * (k0 - 1.0) / k1
  end

  def round_box(x, y, z, half_x, half_y, half_z, rounding)
    qx = x.abs - half_x + rounding
    qy = y.abs - half_y + rounding
    qz = z.abs - half_z + rounding
    ox = qx > 0.0 ? qx : 0.0
    oy = qy > 0.0 ? qy : 0.0
    oz = qz > 0.0 ? qz : 0.0
    inside = qx > qy ? qx : qy
    inside = qz if qz > inside
    inside = 0.0 if inside > 0.0
    Math.sqrt((ox * ox) + (oy * oy) + (oz * oz)) + inside - rounding
  end

  def capsule(x, y, z, start, finish, radius)
    pax = x - start[0]
    pay = y - start[1]
    paz = z - start[2]
    bax = finish[0] - start[0]
    bay = finish[1] - start[1]
    baz = finish[2] - start[2]
    h = ((pax * bax) + (pay * bay) + (paz * baz)) / ((bax * bax) + (bay * bay) + (baz * baz))
    h = 0.0 if h < 0.0
    h = 1.0 if h > 1.0
    dx = pax - (bax * h)
    dy = pay - (bay * h)
    dz = paz - (baz * h)
    Math.sqrt((dx * dx) + (dy * dy) + (dz * dz)) - radius
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
    side = -y if -y > side
    side = y - height if y - height > side
    side
  end

  # Ring standing in the xy plane (its axis along z)
  def torus_xy(x, y, z, ring_radius, tube_radius)
    q = Math.sqrt((x * x) + (y * y)) - ring_radius
    Math.sqrt((q * q) + (z * z)) - tube_radius
  end

  # Cylinder along y, centered on the origin, with edges rounded by rounding
  def cylinder(x, y, z, radius, half_height, rounding = 0.0)
    dx = Math.sqrt((x * x) + (z * z)) - radius + rounding
    dy = y.abs - half_height + rounding
    ox = dx > 0.0 ? dx : 0.0
    oy = dy > 0.0 ? dy : 0.0
    inside = dx > dy ? dx : dy
    inside = 0.0 if inside > 0.0
    Math.sqrt((ox * ox) + (oy * oy)) + inside - rounding
  end

  # Frustum along y between y = -half_height (bottom_radius) and y = half_height (top_radius)
  # rubocop:disable-next Metrics/CyclomaticComplexity
  def capped_cone(x, y, z, half_height, bottom_radius, top_radius)
    qx = Math.sqrt((x * x) + (z * z))
    qy = y
    k2x = top_radius - bottom_radius
    k2y = 2.0 * half_height
    end_radius = qy < 0.0 ? bottom_radius : top_radius
    cax = qx - (qx < end_radius ? qx : end_radius)
    cay = qy.abs - half_height
    t = (((top_radius - qx) * k2x) + ((half_height - qy) * k2y)) / ((k2x * k2x) + (k2y * k2y))
    t = 0.0 if t < 0.0
    t = 1.0 if t > 1.0
    cbx = qx - top_radius + (k2x * t)
    cby = qy - half_height + (k2y * t)
    sign = cbx < 0.0 && cay < 0.0 ? -1.0 : 1.0
    a = (cax * cax) + (cay * cay)
    b = (cbx * cbx) + (cby * cby)
    sign * Math.sqrt(a < b ? a : b)
  end

  # Cone from point a (radius_a) to point b (radius_b), capped at both ends
  # rubocop:disable-next Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def cone_between(x, y, z, a, b, radius_a, radius_b)
    bax = b[0] - a[0]
    bay = b[1] - a[1]
    baz = b[2] - a[2]
    pax = x - a[0]
    pay = y - a[1]
    paz = z - a[2]
    rba = radius_b - radius_a
    baba = (bax * bax) + (bay * bay) + (baz * baz)
    papa = (pax * pax) + (pay * pay) + (paz * paz)
    paba = ((pax * bax) + (pay * bay) + (paz * baz)) / baba
    across2 = papa - (paba * paba * baba)
    across = across2 > 0.0 ? Math.sqrt(across2) : 0.0
    cax = across - (paba < 0.5 ? radius_a : radius_b)
    cax = 0.0 if cax < 0.0
    cay = (paba - 0.5).abs - 0.5
    f = ((rba * (across - radius_a)) + (paba * baba)) / ((rba * rba) + baba)
    f = 0.0 if f < 0.0
    f = 1.0 if f > 1.0
    cbx = across - radius_a - (f * rba)
    cby = paba - f
    sign = cbx < 0.0 && cay < 0.0 ? -1.0 : 1.0
    first = (cax * cax) + (cay * cay * baba)
    second = (cbx * cbx) + (cby * cby * baba)
    sign * Math.sqrt(first < second ? first : second)
  end

  # Regular polygon prism along y between y = -half_height and y = half_height, whose apothem (the distance from
  # its axis to the middle of a side) goes from bottom_apothem to top_apothem. Exact on the sides, a slight
  # underestimate near the corners.
  def ngon_frustum(x, y, z, sides, half_height, bottom_apothem, top_apothem)
    sector = 2.0 * Math::PI / sides
    angle = Math.atan2(z, x)
    angle = ((angle + (sector * 0.5)) % sector) - (sector * 0.5)
    across = Math.sqrt((x * x) + (z * z)) * Math.cos(angle)
    t = ((y / half_height) + 1.0) * 0.5
    t = 0.0 if t < 0.0
    t = 1.0 if t > 1.0
    apothem = bottom_apothem + ((top_apothem - bottom_apothem) * t)
    slope = (top_apothem - bottom_apothem) / (2.0 * half_height)
    side = (across - apothem) / Math.sqrt(1.0 + (slope * slope))
    cap = y.abs - half_height
    side > cap ? side : cap
  end

  # smoothing is the distance over which the two shapes blend into each other
  def smooth_union(a, b, smoothing)
    return (a < b ? a : b) if smoothing <= 0

    h = 0.5 + (0.5 * (b - a) / smoothing)
    h = 0.0 if h < 0.0
    h = 1.0 if h > 1.0
    b + ((a - b) * h) - (smoothing * h * (1.0 - h))
  end

  # Only what is inside both
  def smooth_intersect(a, b, smoothing)
    return (a > b ? a : b) if smoothing <= 0

    h = 0.5 - (0.5 * (b - a) / smoothing)
    h = 0.0 if h < 0.0
    h = 1.0 if h > 1.0
    b + ((a - b) * h) + (smoothing * h * (1.0 - h))
  end

  # a with b cut away
  def smooth_subtract(a, b, smoothing)
    return (a > -b ? a : -b) if smoothing <= 0

    h = 0.5 - (0.5 * (a + b) / smoothing)
    h = 0.0 if h < 0.0
    h = 1.0 if h > 1.0
    a + ((-b - a) * h) + (smoothing * h * (1.0 - h))
  end
end
