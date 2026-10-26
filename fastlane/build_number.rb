# frozen_string_literal: true

# Picks the build number (CFBundleVersion) the `release` lane stamps into the generated project
# (#183). Pure Ruby, no fastlane, so `ruby fastlane/test/build_number_test.rb` tests it offline.
#
# The `version` file stays the source of the marketing version and holds a *floor* for the build
# number. Nothing here writes to it: the chosen number goes only into the generated .xcodeproj,
# so `verify` and other local runs never change a tracked file.
#
# - With an App Store Connect API key, TestFlight is the source of truth: the build number is
#   max(latest TestFlight build, version file) + 1, so consecutive releases upload without anyone
#   editing `version`.
# - Without a key the lane cannot upload (it stops after the .ipa), so there is nothing to collide
#   with: it stamps the version file's number unchanged and says the number was not checked.
# - An explicit `build_number:` wins, but with a key it must still be above TestFlight's latest,
#   checked before archiving rather than rejected at upload.
module BuildNumber
  Plan = Struct.new(:build_number, :source, :explanation, keyword_init: true)

  class Error < StandardError; end

  module_function

  # An Integer from the version file, TestFlight or the command line. TestFlight returns an
  # Integer for plain numbers and a String otherwise; anything but a non-negative whole number is
  # an error rather than a guess.
  def parse(value, source:)
    return value if value.is_a?(Integer) && value >= 0

    string = value.to_s.strip
    raise Error, "#{source} build number #{value.inspect} is not a whole number" unless string.match?(/\A\d+\z/)

    Integer(string, 10)
  end

  def next_after(version_file_build:, testflight_latest:)
    [version_file_build, testflight_latest].max + 1
  end

  # version_file_build: second line of `version`.
  # testflight_latest: latest TestFlight build number, or nil when there is no API key.
  # requested: an explicit `build_number:` lane option, or nil.
  def plan(version_file_build:, testflight_latest: nil, requested: nil)
    file = parse(version_file_build, source: 'version file')
    latest = testflight_latest.nil? ? nil : parse(testflight_latest, source: 'TestFlight')

    if requested
      number = parse(requested, source: 'requested')
      if latest && number <= latest
        raise Error, "Requested build number #{number} is not above TestFlight's latest (#{latest}); " \
                     'App Store Connect would reject the upload. Omit build_number: to use ' \
                     "#{next_after(version_file_build: file, testflight_latest: latest)}."
      end
      checked = latest ? "above TestFlight's latest (#{latest})" : 'not checked against TestFlight (no API key)'
      return Plan.new(build_number: number, source: :requested,
                      explanation: "build number #{number} from build_number:, #{checked}")
    end

    if latest
      number = next_after(version_file_build: file, testflight_latest: latest)
      return Plan.new(build_number: number, source: :testflight,
                      explanation: "build number #{number} = max(TestFlight latest #{latest}, " \
                                   "version file #{file}) + 1")
    end

    Plan.new(build_number: file, source: :version_file,
             explanation: "build number #{file} from the version file, not checked against TestFlight " \
                          '(no API key, so this run does not upload)')
  end
end
