require 'xcodeproj'

project = Xcodeproj::Project.open('Abbay.xcodeproj')

versionFile = File.read('version').split
marketingVersion = versionFile[0]
projectVersion = versionFile[1]

project.targets.each do |target|
    if target.name == 'Abbay' then
        target.build_configurations.each do |config|
            config.build_settings['MARKETING_VERSION'] = marketingVersion
            config.build_settings['CURRENT_PROJECT_VERSION'] = projectVersion
        end
    end
end

project.save
