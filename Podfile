platform :ios, '16.0'
source 'https://github.com/CocoaPods/Specs.git'
use_frameworks!

post_install do |installer|

    installer.pods_project.targets.each do |target|

      target.build_configurations.each do |config|
        config.build_settings["EXCLUDED_ARCHS[sdk=iphonesimulator*]"] = "arm64"
        config.build_settings.delete 'IPHONEOS_DEPLOYMENT_TARGET'
      end
      target.respond_to?(:product_type) and target.product_type == "com.apple.product-type.bundle"
            target.build_configurations.each do |config|
                config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
      end
  end
end

target 'CrazyDashboard' do

###DEBUG
pod 'LookinServer', :configurations => ['Debug']
pod 'Bugly'

##PooTools
pod 'PooTools/Core', :git => 'https://github.com/crazypoo/PTools.git'
pod 'PooTools/DEBUG', :git => 'https://github.com/crazypoo/PTools.git'
pod 'PooTools/WhatsNewsKit', :git => 'https://github.com/crazypoo/PTools.git'
pod 'PooTools/LocationPermission', :git => 'https://github.com/crazypoo/PTools.git'
pod 'PooTools/Flag', :git => 'https://github.com/crazypoo/PTools.git'
pod 'PooTools/Motion', :git => 'https://github.com/crazypoo/PTools.git'
pod 'PooTools/NetWork', :git => 'https://github.com/crazypoo/PTools.git'
pod 'SwiftyUserDefaults'
end

target 'PTSpeed' do

###DEBUG
pod 'LookinServer', :configurations => ['Debug']
pod 'Bugly'

##PooTools
pod 'PooTools/Core', :git => 'https://github.com/crazypoo/PTools.git'
pod 'PooTools/DEBUG', :git => 'https://github.com/crazypoo/PTools.git'
pod 'PooTools/WhatsNewsKit', :git => 'https://github.com/crazypoo/PTools.git'
pod 'PooTools/LocationPermission', :git => 'https://github.com/crazypoo/PTools.git'
pod 'PooTools/Flag', :git => 'https://github.com/crazypoo/PTools.git'
pod 'PooTools/Motion', :git => 'https://github.com/crazypoo/PTools.git'
pod 'PooTools/NetWork', :git => 'https://github.com/crazypoo/PTools.git'
pod 'SwiftyUserDefaults'
end
