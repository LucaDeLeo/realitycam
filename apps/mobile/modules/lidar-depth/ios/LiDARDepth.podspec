Pod::Spec.new do |s|
  s.name           = 'LiDARDepth'
  s.version        = '1.0.0'
  s.summary        = 'LiDAR depth capture for Expo'
  s.description    = 'Native module for capturing LiDAR depth data on iPhone Pro devices'
  s.author         = 'RealityCam'
  s.homepage       = 'https://github.com/realitycam'
  s.platforms      = { :ios => '15.1' }
  s.source         = { :git => '' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  s.source_files = '**/*.{h,m,mm,swift}'
  s.frameworks = 'ARKit'
end
