Pod::Spec.new do |s|
  s.name             = 'AutoSDK'
  s.version          = '1.26.0'
  s.summary          = 'Embedded iOS JavaScript automation SDK'
  s.description      = 'A client-side automation runtime with a JavaScriptCore bridge and injectable UI adapter.'
  s.homepage         = 'https://github.com/huihui0115/ios-auto-sdk'
  s.license          = { :type => 'Commercial' }
  s.author           = { 'AutoSDK' => 'sdk@example.com' }
  s.platform         = :ios, '14.0'
  s.static_framework = true
  s.source           = { :git => 'https://github.com/huihui0115/ios-auto-sdk.git', :tag => s.version.to_s }
  s.source_files     = 'Sources/AutoSDK/**/*.{h,m}'
  s.public_header_files = 'Sources/AutoSDK/include/*.h'
  s.frameworks       = 'Foundation', 'UIKit', 'QuartzCore', 'JavaScriptCore', 'Network', 'Vision', 'AVFoundation', 'AudioToolbox', 'Photos', 'ImageIO', 'UserNotifications', 'CoreLocation'
  s.libraries        = 'z', 'sqlite3'
  s.requires_arc     = true
end
