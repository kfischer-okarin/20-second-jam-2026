require 'app/render/rot3'
require 'app/render/rng'
require 'app/render/noise3'
require 'app/render/sdf'
require 'app/render/splat_model'
require 'app/render/sdf_baker'

def tick(args)
  args.outputs.labels  << [640, 500, 'Hello World!', 5, 1]
  args.outputs.labels  << [640, 460, 'Go to docs/docs.html and read it!', 5, 1]
  args.outputs.labels  << [640, 420, 'Join the Discord! https://discord.dragonruby.org', 5, 1]
end
