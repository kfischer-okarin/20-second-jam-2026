# Row-major 3x3 rotation matrices as flat 9-element arrays.
# Coordinates: x right, y up, z towards the viewer.
module Rot3
  IDENTITY = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0].freeze

  extend self

  def rot_x(angle)
    c = Math.cos(angle)
    s = Math.sin(angle)
    [1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c]
  end

  def rot_y(angle)
    c = Math.cos(angle)
    s = Math.sin(angle)
    [c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c]
  end

  def rot_z(angle)
    c = Math.cos(angle)
    s = Math.sin(angle)
    [c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0]
  end

  # Rotation around a unit axis (Rodrigues)
  def axis_angle(x, y, z, angle)
    c = Math.cos(angle)
    s = Math.sin(angle)
    t = 1.0 - c
    [
      (t * x * x) + c, (t * x * y) - (s * z), (t * x * z) + (s * y),
      (t * x * y) + (s * z), (t * y * y) + c, (t * y * z) - (s * x),
      (t * x * z) - (s * y), (t * y * z) + (s * x), (t * z * z) + c
    ]
  end

  def mul(a, b)
    [
      (a[0] * b[0]) + (a[1] * b[3]) + (a[2] * b[6]),
      (a[0] * b[1]) + (a[1] * b[4]) + (a[2] * b[7]),
      (a[0] * b[2]) + (a[1] * b[5]) + (a[2] * b[8]),
      (a[3] * b[0]) + (a[4] * b[3]) + (a[5] * b[6]),
      (a[3] * b[1]) + (a[4] * b[4]) + (a[5] * b[7]),
      (a[3] * b[2]) + (a[4] * b[5]) + (a[5] * b[8]),
      (a[6] * b[0]) + (a[7] * b[3]) + (a[8] * b[6]),
      (a[6] * b[1]) + (a[7] * b[4]) + (a[8] * b[7]),
      (a[6] * b[2]) + (a[7] * b[5]) + (a[8] * b[8])
    ]
  end

  def apply(matrix, x, y, z)
    m0, m1, m2, m3, m4, m5, m6, m7, m8 = matrix
    [
      (m0 * x) + (m1 * y) + (m2 * z),
      (m3 * x) + (m4 * y) + (m5 * z),
      (m6 * x) + (m7 * y) + (m8 * z)
    ]
  end
end
