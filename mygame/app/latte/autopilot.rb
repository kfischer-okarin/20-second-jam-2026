# Pours by itself, for trying the simulation without a mouse (see GameCli). A pour is a list of keyframes
# [seconds, aim_x, aim_z, height above the coffee, tilt]; controls move linearly between them.
class Autopilot
  POURS = {
    # A high pour to lighten the base, a low pour that grows a blob, then lifted and pulled through it
    heart: [
      [0.0, 0.0, -0.5, 5.5, 0.0], [1.0, 0.0, -0.5, 6.5, 0.9], [3.5, 0.4, -0.2, 6.5, 0.95],
      [4.0, 0.0, -0.8, 0.7, 1.05], [6.4, 0.0, -0.4, 0.6, 1.15], [6.9, 0.0, -3.6, 3.0, 0.85],
      [7.9, 0.0, 3.6, 3.4, 0.75], [8.2, 0.0, 4.0, 4.5, 0.0], [9.5, 4.5, 6.0, 5.0, 0.0], [99.0, 4.5, 6.0, 5.0, 0.0]
    ],
    # Low pour wiggled side to side while drawing back, then pulled through: a rosetta
    rosetta: [
      [0.0, 0.0, 0.0, 6.0, 0.0], [1.0, 0.0, 0.0, 6.5, 0.9], [3.0, 0.0, 0.0, 6.5, 0.95],
      [3.6, 0.0, -2.6, 0.8, 1.05], *Array.new(14) { |i|
        [4.0 + (i * 0.28), (i.even? ? -1.1 : 1.1) * (1.0 - (i * 0.04)), -2.6 + (i * 0.38), 0.8, 1.05]
      },
      [8.2, 0.0, 2.9, 0.8, 1.0], [8.5, 0.0, 3.0, 3.2, 0.85], [9.1, 0.0, -3.4, 3.4, 0.75],
      [9.4, 0.0, -3.6, 4.5, 0.0], [99.0, 0.0, -3.6, 4.5, 0.0]
    ],
    # Wanders off the cup and pours onto the saucer and the table
    spill: [
      [0.0, 0.0, 0.0, 5.0, 0.0], [1.0, 3.0, 2.0, 4.0, 1.0], [2.0, 6.5, 2.0, 4.0, 1.0], [3.5, 9.0, 6.0, 5.0, 1.1],
      [5.0, -8.0, 8.0, 6.0, 1.1], [6.0, -5.2, 0.0, 2.0, 1.0], [7.0, 0.0, -5.0, 2.0, 1.0], [7.5, 0.0, -5.0, 2.0, 0.0],
      [99.0, 0.0, -5.0, 2.0, 0.0]
    ]
  }.freeze

  def initialize(pour)
    @keys = POURS.fetch(pour)
  end

  def controls(t)
    index = 0
    index += 1 while index + 1 < @keys.length && @keys[index + 1][0] <= t
    from = @keys[index]
    to = @keys[[index + 1, @keys.length - 1].min]
    span = to[0] - from[0]
    f = span.positive? ? ((t - from[0]) / span).clamp(0.0, 1.0) : 0.0
    x, z, height, tilt = (1..4).map { |i| from[i] + ((to[i] - from[i]) * f) }
    { aim_x: x, aim_z: z, raise: 0.0, tip: 0.0, pour: false, height: height, tilt: tilt }
  end
end
