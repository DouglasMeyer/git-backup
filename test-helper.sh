#!/bin/sh

backup_cmd=$(pwd)/git-backup.sh
restore_cmd=$(pwd)/git-restore.sh
test_path=$(mktemp --directory --tmpdir tmp.$(basename $0 .sh).XXXXX)
assertions=0
failures=0


### Ending actions
on_exit() {
  status=$?

  # clean test files
  if [ -d $test_path ] ; then
    rm -rf "$test_path"
  fi

  # print counts
  echo "$assertions assertions, $failures failures."
  if [ "$status" -ne 0 ] ; then
    echo "Something went wrong in $0"
  else
    [ $failures -eq 0 ]
    exit $?
  fi
}
trap on_exit EXIT


### Assertions
assert() { # assertion, message
  assertions=$(( $assertions + 1 ))
  if [ $1 -ne 0 ] ; then
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
  assert_equal "$expected" "$actual"
}


### Fixtures
cd "$test_path"

## Local Project
mkdir local_project
cd local_project
git init >/dev/null
echo "First content" > first_file
git add first_file

git commit -m "First commit" >/dev/null


## Remote Project
cd "$test_path"
git clone local_project remote_project >/dev/null
cd remote_project

git config --add "apply.whitespace" "fix"

echo "# My update script" > .git/hooks/update
git checkout -b my_branch 2>/dev/null

echo "Ignore me" > ignore\ file\ 1
echo "Ignore me" > ignore\ file\ 2
echo "ignore\ file\ ?" > .gitignore
git add .gitignore

echo "Pre stash content" > first_file
git add first_file
git commit -m "Pre stash commit" >/dev/null

echo "Stashed content" > first_file
git stash save "My stash" >/dev/null

echo "Branch content" > first_file
git add first_file
git commit -m "Branch commit" >/dev/null

git checkout master 2>/dev/null
echo "Post-branch content" > first_file
git add first_file
git commit -m "Post branch commit" >/dev/null

git checkout my_branch 2>/dev/null

echo "Cached content" > first_file
git add first_file

echo "Working Copy content" > first_file

echo "Not tracked content" > not\ tracked\ 1
echo "Not tracked content" > not\ tracked\ 2
