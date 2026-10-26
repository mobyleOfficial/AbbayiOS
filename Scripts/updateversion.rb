require 'xcodeproj'

project = Xcodeproj::Project.open('Abbay.xcodeproj')

versionFile = File.read('version').split
marketingVersion = versionFile[0]
projectVersion = versionFile[1]

project.targets.each do |target|
    # The app and its Siri extension must ship the same version (App Store Connect rejects a
    # mismatch). The embedded NetworkProvider framework needs one too: its generated Info.plist
    # has no CFBundleShortVersionString / CFBundleVersion without it, and App Store validation
    # rejects the upload. The test bundle follows so its Info.plist resolves.
    if ['Abbay', 'AbbayIntents', 'NetworkProvider', 'AbbayTests'].include?(target.name) then
        target.build_configurations.each do |config|
            config.build_settings['MARKETING_VERSION'] = marketingVersion
            config.build_settings['CURRENT_PROJECT_VERSION'] = projectVersion
        end
    end
end

project.save
