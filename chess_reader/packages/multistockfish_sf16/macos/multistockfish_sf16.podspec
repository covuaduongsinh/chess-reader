#
# macOS build of the multistockfish_sf16 FFI engine.
#
# This mirrors ios/multistockfish_sf16.podspec exactly (same sources, same NNUE
# download, same incbin layout) so it inherits the known-good iOS setup. The
# only differences are macOS-specific:
#   * platform :osx instead of :ios; depends on FlutterMacOS.
#   * NEON is enabled only for the arm64 slice — macOS builds are universal
#     (arm64 + x86_64) and `-DUSE_NEON` is invalid on x86_64. USE_POPCNT is left
#     on for all archs (Stockfish falls back to __builtin_popcountll, which is
#     safe without -mpopcnt).
#   * LTO is dropped to keep universal builds robust.
#
require 'yaml'

pubspec = YAML.load(File.read(File.join(__dir__, '../pubspec.yaml')))

Pod::Spec.new do |s|
  s.name             = 'multistockfish_sf16'
  s.version          = pubspec['version']
  s.summary          = pubspec['description']
  s.homepage         = pubspec['homepage']
  s.license          = { :file => '../LICENSE', :type => 'GPL' }
  s.author           = { 'lichess.org' => 'contact@lichess.org' }
  s.source = { :git => pubspec['repository'], :tag => s.version.to_s }
  s.source_files = 'Classes/**/*', 'Stockfish16/src/**/*'
  s.exclude_files = [
    'Stockfish16/src/Makefile',
    'Stockfish16/src/main.cpp',
    'Stockfish16/src/incbin/UNLICENCE',
  ]
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '14.0'
  s.swift_version = '5.0'

  base = '-std=c++17 -DUSE_PTHREADS -DIS_64BIT -DUSE_POPCNT'
  opt  = '-fno-exceptions -DNDEBUG -O3'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    # Debug / unconditioned: portable, no ISA-specific flags.
    'OTHER_CPLUSPLUSFLAGS' => base,
    # Optimized configs (all archs).
    'OTHER_CPLUSPLUSFLAGS[config=Profile]' => "#{base} #{opt}",
    'OTHER_CPLUSPLUSFLAGS[config=Release]' => "#{base} #{opt}",
    # arm64 optimized configs additionally enable NEON dotprod (Apple Silicon).
    'OTHER_CPLUSPLUSFLAGS[config=Profile][arch=arm64]' => "#{base} #{opt} -DUSE_NEON=8",
    'OTHER_CPLUSPLUSFLAGS[config=Release][arch=arm64]' => "#{base} #{opt} -DUSE_NEON=8",
  }

  s.script_phase = [
    {
      :execution_position => :before_compile,
      :name => 'Download nnue',
      :script => "[ -e 'nn-5af11540bbfe.nnue' ] || curl --location --remote-name 'https://tests.stockfishchess.org/api/nn/nn-5af11540bbfe.nnue'"
    }
  ]
end
