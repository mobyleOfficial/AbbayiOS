require 'xcodeproj'

project = Xcodeproj::Project.open('Abbay.xcodeproj')

versionFile = File.read('version').split
marketingVersion = versionFile[0]
projectVersion = versionFile[1]

project.targets.each do |target|
    # The app and its Siri extension must ship the same version (App Store Connect rejects a
    # mismatch); the test bundle follows so its Info.plist resolves too.
    if ['Abbay', 'AbbayIntents', 'AbbayTests'].include?(target.name) then
        target.build_configurations.each do |config|
            config.build_settings['MARKETING_VERSION'] = marketingVersion
            config.build_settings['CURRENT_PROJECT_VERSION'] = projectVersion
        end
    end
end

project.save
