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

echo "Ignore me" > ignore_file
echo "ignore_file" > .gitignore
git add .gitignore

echo "Branch content" > first_file
git add first_file
git commit -m "Branch commit" >/dev/null

echo "Stashed content" > first_file
git stash save "My stash" >/dev/null

echo "Cached content" > first_file
git add first_file

echo "Working Copy content" > first_file

echo "Untracked content" > untracked_file

$backup_cmd --untracked --ignored

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

# Test HEAD should be where we were
head=$(cat .git/HEAD)
assert_equal "my_branch" "${head##*/}"

# Test remote should get set
assert_equal "${test_path}/local_project" "$(git config --get "remote.origin.url")"

# Test config should get copied
assert_equal "fix" "$(git config --get --local "apply.whitespace")"

# Test hooks should get copied
assert_equal "# My update script" "$(cat .git/hooks/update)"

# Test branches should get copied
assert_equal "Branch content" "$(git show my_branch:first_file)"

# Test cached changes should get restored
git diff --cached | grep -q "Cached content"
assert $? "$LINENO: expecetd \"Cached content\" to be part of the cache"

# Test working copy changes should get restored
assert_equal "Working Copy content" "$(cat ./first_file)"
git diff --cached | grep -v -q "Working Copy content"
assert $? "$LINENO: expecetd \"Working Copy content\" to be part of the content"

# Test untracked files get restored
assert_equal "Untracked content" "$(cat ./untracked_file)"
assert_equal "" "$(git show untracked_file)"

# Test ignored files get restored
assert_equal "Ignore me" "$(cat ./ignore_file)"
assert_equal "" "$(git show ignore_file)"

# Test stashed changes get restored
git stash show -p | grep -q "Stashed content"
assert $? "$LINENO: stashed content should be stashed"
git stash list | grep -q "stash@{0}: On my_branch: My stash"
assert $? "$LINENO: stash should have correct name"
