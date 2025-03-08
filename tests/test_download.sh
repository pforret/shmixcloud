#!/usr/bin/env bash
# test functions should start with test_
# using https://github.com/pgrange/bash_unit
#  fail
#  assert
#  assert "test -e /tmp/the_file"
#  assert_fails "grep this /tmp/the_file" "should not write 'this' in /tmp/the_file"
#  assert_status_code 25 code
#  assert_equals "a string" "another string" "a string should be another string"
#  assert_not_equals "a string" "a string" "a string should be different from another string"
#  fake ps echo hello world

root_folder=$(cd .. && pwd) # tests/.. is root folder
# shellcheck disable=SC2012
# shellcheck disable=SC2035
root_script=$(find "$root_folder"  -maxdepth 1 -name "*.sh" | head -1) # normally there should be only 1

test_download_one() {
  # script without parameters should give usage info
  "$root_script" -N 1 -f -v download https://www.mixcloud.com/oldiespopcorn/
  assert_exists "output/"
}
