# frozen_string_literal: true

# Run with: ruby fastlane/test/build_number_test.rb (plain Ruby, not `bundle exec`: minitest ships
# with Ruby but is not in the Gemfile).

require 'minitest/autorun'
require_relative '../build_number'

class BuildNumberTest < Minitest::Test
  def test_with_testflight_uses_latest_plus_one_when_testflight_is_ahead
    plan = BuildNumber.plan(version_file_build: '2', testflight_latest: 7)
    assert_equal 8, plan.build_number
    assert_equal :testflight, plan.source
  end

  def test_with_testflight_uses_version_file_plus_one_when_file_is_ahead
    # Someone raised the floor in `version` on purpose; it is respected, never gone below.
    assert_equal 11, BuildNumber.plan(version_file_build: '10', testflight_latest: 7).build_number
  end

  def test_with_testflight_equal_numbers_still_increment
    assert_equal 3, BuildNumber.plan(version_file_build: '2', testflight_latest: 2).build_number
  end

  def test_first_upload_with_no_testflight_builds
    # The lane asks for initial_build_number: 0, so an empty TestFlight reads as 0.
    assert_equal 3, BuildNumber.plan(version_file_build: '2', testflight_latest: 0).build_number
  end

  def test_consecutive_releases_increase_without_editing_version
    first = BuildNumber.plan(version_file_build: '2', testflight_latest: 2).build_number
    second = BuildNumber.plan(version_file_build: '2', testflight_latest: first).build_number
    assert_operator second, :>, first
  end

  def test_testflight_string_number_is_parsed
    assert_equal 13, BuildNumber.plan(version_file_build: 2, testflight_latest: '12').build_number
  end

  def test_without_key_uses_version_file_unchanged
    plan = BuildNumber.plan(version_file_build: "2\n")
    assert_equal 2, plan.build_number
    assert_equal :version_file, plan.source
    assert_match(/not checked against TestFlight/, plan.explanation)
  end

  def test_requested_above_testflight_is_used
    plan = BuildNumber.plan(version_file_build: '2', testflight_latest: 7, requested: '20')
    assert_equal 20, plan.build_number
    assert_equal :requested, plan.source
  end

  def test_requested_not_above_testflight_fails_before_archiving
    error = assert_raises(BuildNumber::Error) do
      BuildNumber.plan(version_file_build: '2', testflight_latest: 7, requested: '7')
    end
    assert_match(/not above TestFlight's latest \(7\)/, error.message)
    assert_match(/use 8/, error.message)
  end

  def test_requested_without_key_is_used_unchecked
    plan = BuildNumber.plan(version_file_build: '2', requested: 1)
    assert_equal 1, plan.build_number
    assert_match(/not checked/, plan.explanation)
  end

  def test_non_numeric_values_are_errors
    assert_raises(BuildNumber::Error) { BuildNumber.plan(version_file_build: '') }
    assert_raises(BuildNumber::Error) { BuildNumber.plan(version_file_build: '2.1') }
    assert_raises(BuildNumber::Error) { BuildNumber.plan(version_file_build: '2', testflight_latest: '1.0.3') }
    assert_raises(BuildNumber::Error) { BuildNumber.plan(version_file_build: '2', requested: '-1') }
  end
end
