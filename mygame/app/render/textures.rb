# Procedural textures, created as pixel arrays at start so no image files are needed
module Textures
  extend self

  def create(args)
    radial(args, :splat, 32) do |distance_squared|
      gaussian(distance_squared)
    end
    radial(args, :disc, 32) do |distance_squared|
      disc(distance_squared)
    end
    radial(args, :hard, 32) do |distance_squared|
      hard(distance_squared)
    end
    radial(args, :ring, 96) do |distance_squared|
      ring(Math.sqrt(distance_squared))
    end
    PixelFont.create_atlas(args)
  end

  # White texture whose alpha is a function of the squared distance from its center (1.0 at the edge)
  def radial(args, name, size)
    pixel_array = args.pixel_array(name)
    pixel_array.w = size
    pixel_array.h = size
    pixel_array.pixels = Array.new(size * size) do |index|
      dx = ((((index % size) + 0.5) / size) * 2.0) - 1.0
      dy = ((((index / size).floor + 0.5) / size) * 2.0) - 1.0
      alpha = yield((dx * dx) + (dy * dy)).clamp(0.0, 1.0)
      ((alpha * 255).round << 24) | 0xFFFFFF
    end
  end

  # Falls off to exactly zero at the edge so splats never show a square border
  def gaussian(distance_squared)
    return 0.0 if distance_squared >= 1.0

    edge = Math.exp(-4.0)
    (Math.exp(-4.0 * distance_squared) - edge) / (1.0 - edge)
  end

  # Opaque in its middle, falling off smoothly towards the edge: model splats that are drawn large close up need
  # it to cover the gaps between neighbours, which a gaussian leaves almost transparent
  def disc(distance_squared)
    d = Math.sqrt(distance_squared)
    return 0.0 if d >= 1.0

    t = ((1.0 - d) / 0.6).clamp(0.0, 1.0)
    t * t * (3.0 - (2.0 * t))
  end

  # A gaussian cut off sharply where it falls to about half: a crisp ellipse a little less than half as wide as
  # the sprite, so neighbouring splats meet without blending into each other
  def hard(distance_squared)
    t = ((Math.exp(-4.5 * distance_squared) - 0.32) / 0.2).clamp(0.0, 1.0)
    t * t * (3.0 - (2.0 * t))
  end

  def ring(r)
    x = (r - 0.86) / 0.07
    Math.exp(-x * x)
  end
end
