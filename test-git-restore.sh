#!/bin/bash

backup_cmd=$(pwd)/git-backup.sh
restore_cmd=$(pwd)/git-restore.sh
test_path=$(mktemp --directory --tmpdir tmp.$(basename $0 .sh).XXXXX)
assertions=0
failures=0

on_exit() {
  status=$?

  rm -rf "$test_path"

  echo "$assertions assertions, $failures failures."
  if [ "$status" -ne 0 ] ; then
    echo "Something went wrong in $0"
  else
    [ $failures -eq 0 ]
    exit $?
  fi
}
trap on_exit EXIT

assert() { # assertion, message
  assertions=$(( $assertions + 1 ))
  if [ "$1" -ne 0 ] ; then
    echo "$2"
    failures=$(( $failures + 1 ))
  fi
}
assert_equal() { # expected, actual
  [ "$1" == "$2" ]; assert $? "Expected \"$1\" but was \"$2\"."
}
files_equal() { # expected, actual
  [ -f "$1" ]
  assert $? "Expected file \"$1\" doesn't exist."
  [ -f "$2" ]
  assert $? "Test file \"$2\" doesn't exist."
  expected=$(md5sum "$1" 2>/dev/null | cut -c -32)
  actual=$(md5sum "$2" 2>/dev/null | cut -c -32)
  [ "$expected" = "$actual" ]
  assert $? "${2#$build_path/} was not equal to ${1#$build_path/}"
}


### Setup
cd "$test_path"
mkdir local_project; cd local_project
git init >/dev/null
echo "First content" > first_file
git add first_file
git commit -m "First commit" >/dev/null
$backup_cmd

cd "$test_path"
git clone local_project remote_project >/dev/null
cd remote_project
git config --add "apply.whitespace" "fix"
echo "# My update script" > .git/hooks/update
git checkout -b my_branch 2>/dev/null
echo "Branch content" > first_file
git add first_file
git commit -m "Branch commit" >/dev/null
$backup_cmd

mkdir "$test_path/restore"; cd "$test_path/restore"
$restore_cmd ../local_project/local_project.tar
$restore_cmd ../remote_project/remote_project.tar


### Tests

# Test git files get populated for local_project
cd "$test_path/restore/local_project"
[ -f .git/config ];  assert $? "$LINENO: .git/config should exist"
[ -d .git/hooks ];   assert $? "$LINENO: .git/hooks should exist"
[ -d .git/objects ]; assert $? "$LINENO: .git/objects should exist"
[ -d .git/refs ];    assert $? "$LINENO: .git/refs should exist"


# Test git files get populates for remote_project
cd "$test_path/restore/remote_project"
[ -f .git/config ];  assert $? "$LINENO: .git/config should exist"
[ -d .git/hooks ];   assert $? "$LINENO: .git/hooks should exist"
[ -d .git/objects ]; assert $? "$LINENO: .git/objects should exist"
[ -d .git/refs ];    assert $? "$LINENO: .git/refs should exist"

# Test remote should get set
assert_equal "${test_path}/local_project" "$(git config --get "remote.origin.url")"

# Test config should get copied
assert_equal "fix" "$(git config --get --local "apply.whitespace")"

# Test hooks should get copied
assert_equal "# My update script" "$(cat .git/hooks/update)"

# Test branches should get copied
git checkout my_branch 2>/dev/null; assert $? "$LINENO: by_branch should exist."
assert_equal "Branch content" "$(cat ./first_file)"
