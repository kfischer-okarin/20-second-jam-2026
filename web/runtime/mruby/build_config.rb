# mruby for the web runtime, built by web/build. The gems and defines keep it as close to DragonRuby's mruby as the
# game needs: 64-bit Integers that overflow into Floats (no bigint), Float results from Integer / Integer (see
# float-division.patch), no Rational or Complex.

# The lock file would only repeat the mruby version, which web/build pins
MRuby::Lockfile.disable

def dragonruby_like(conf)
  # Integers are 64 bits wide in DragonRuby too; on wasm32 that needs unboxed values
  conf.cc.defines += %w[MRB_INT64 MRB_NO_BOXING]
  conf.gembox 'stdlib'
  conf.gembox 'stdlib-ext'
  conf.gem core: 'mruby-math'
  conf.gem core: 'mruby-metaprog'
  conf.gem core: 'mruby-method'
  conf.gem core: 'mruby-eval'
  conf.gem core: 'mruby-compiler'
end

# The native build provides mrbc for the cross build, and bin/mruby to check Ruby semantics without a browser
MRuby::Build.new do |conf|
  conf.toolchain
  dragonruby_like(conf)
  conf.gem core: 'mruby-bin-mruby'
end

MRuby::CrossBuild.new('emscripten') do |conf|
  conf.toolchain :emscripten
  conf.cc.flags << '-O3'
  dragonruby_like(conf)
  # mruby-config tells web/build the defines the runtime has to be compiled with to match libmruby
  conf.gem core: 'mruby-bin-config'
end
