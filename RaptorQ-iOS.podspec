Pod::Spec.new do |s|
  s.name         = 'RaptorQ-iOS'
  s.version      = "0.1.0"
  s.summary      = "iOS compatible binding for raptorq rust implementation"
  s.homepage     = "https://github.com/novasamatech/sr25519.c"
  s.license      = 'MIT'
  s.author       = {'Ruslan Rezin' => 'ruslan@novasama.io'}
  s.source       = { :git => 'https://github.com/novasamatech/raptorq-ios',  :tag => "#{s.version}"}

  s.ios.deployment_target = '12.0'
  s.swift_version = '5.0'

  s.vendored_frameworks = 'bindings/xcframework/raptorq.xcframework'
  s.module_name = 'RaptorQ-iOS'
end