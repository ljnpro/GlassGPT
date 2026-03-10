require 'json'

package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

Pod::Spec.new do |s|
  s.name           = 'NativeChat'
  s.version        = package['version']
  s.summary        = 'Native SwiftUI chat interface for Liquid Glass Chat'
  s.description    = 'Full native SwiftUI implementation of the chat app with iOS 26 liquid glass effects'
  s.homepage       = 'https://github.com/ljnpro/liquid-glass-chat'
  s.license        = { :type => 'MIT' }
  s.author         = { 'ljnpro' => 'ljnpro6@gmail.com' }
  s.source         = { :git => '' }

  s.platform       = :ios, '26.0'
  s.swift_version  = '6.0'

  s.source_files   = '**/*.{swift,h,m}'

  s.dependency 'ExpoModulesCore'
  s.dependency 'React-Core'

  s.frameworks     = 'SwiftUI', 'SwiftData', 'Security'
end
