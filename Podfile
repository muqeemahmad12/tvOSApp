platform :tvos, '15.0'
use_frameworks!
inhibit_all_warnings!

target 'TVShowBrowser' do
  pod 'GoogleAds-IMA-tvOS-SDK', '~> 4.15.1'

  # ✅ Explicitly add xcframework paths for tvOS and simulator
  post_install do |installer|
    installer.pods_project.targets.each do |target|
      if target.name == 'GoogleAds-IMA-tvOS-SDK'
        target.build_configurations.each do |config|
          config.build_settings['FRAMEWORK_SEARCH_PATHS'] ||= ['$(inherited)']
          config.build_settings['FRAMEWORK_SEARCH_PATHS'] << '$(PODS_ROOT)/GoogleAds-IMA-tvOS-SDK/GoogleInteractiveMediaAds.xcframework/tvos-arm64'
          config.build_settings['FRAMEWORK_SEARCH_PATHS'] << '$(PODS_ROOT)/GoogleAds-IMA-tvOS-SDK/GoogleInteractiveMediaAds.xcframework/tvos-arm64_x86_64-simulator'
        end
      end
    end
  end
end
