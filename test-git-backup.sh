#!/bin/sh

backup_cmd=$(pwd)/git-backup.sh
test_path=$(mktemp --directory --tmpdir tmp.$(basename $0 .sh).XXXXX)
untar_path="$test_path/output"
assertions=0
failures=0

on_exit() {
  status=$?

  # clean test files
  rm -rf "$test_path"

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

assert() { # assertion, message
  assertions=$(( $assertions + 1 ))
  if [ $1 -ne 0 ] ; then
    echo "$2"
    failures=$(( $failures + 1 ))
  fi
}
files_equal() { # expected, actual
  [ -f "$1" ]
  assert $? "Expected file \"$1\" doesn't exist."
  [ -f "$2" ]
  assert $? "Test file \"$2\" doesn't exist."
  expected=$(md5sum "$1" 2>/dev/null | cut -c -32)
  actual=$(md5sum "$2" 2>/dev/null | cut -c -32)
  [ "$expected" = "$actual" ]
  assert $? "${2#$test_path/} was not equal to ${1#$test_path/}"
}

### Setup
cd "$test_path"
mkdir local_project
cd local_project
git init >/dev/null
echo "First content" > first_file
git add first_file
git commit -m "First commit" >/dev/null

cd "$test_path"
git clone local_project remote_project >/dev/null
cd remote_project
echo "First update" > first_file
git add first_file
git commit -m "First update" >/dev/null

git checkout -b my_branch &>/dev/null
echo "A branch" > first_file
git add first_file
git commit -m "A branch" >/dev/null

setup() {
  rm -rf "$untar_path"
  cd "$test_path/${1-remote}_project"
  mkdir "$untar_path"
}
backup() {
  $backup_cmd $*
  tar=$(pwd)/$(basename $(pwd)).tar
  cd "$untar_path"
  tar xvf $tar >/dev/null
  rm $tar
}


# Test non-remote backup
setup 'local'
$backup_cmd
mv "$test_path/local_project/local_project.tar" "$test_path/local_project.tar"
tar cf "$test_path/tar_project.tar" .
cd "$test_path"
files_equal "$test_path/tar_project.tar" "$test_path/local_project.tar"


# Test config gets backed-up
setup
backup
files_equal "$test_path/remote_project/.git/config" "$untar_path/.git/config"


# Test --no-config doesn't include config
setup
backup --no-config
[ ! -e "$untar_path/.git/config" ]
assert $? "$LINENO: $untar_path/.git/config should not exist"


# Test --no-default doesn't incude defaults
setup
backup --no-default
[ ! -e "$untar_path/.git/config" ]
assert $? "$LINENO: $untar_path/.git/config should not exist"
[ ! -d "$untar_path/.git/hooks" ]
assert $? "$LINENO: $untar_path/.git/hooks should not exist"
[ -d "$untar_path/my_branch" ]
assert $? "$LINENO: $untar_path/my_branch should exist"


# Test --hooks includes hooks
setup
backup --hooks
[ -e "$untar_path/.git/hooks" ]
assert $? "$LINENO: $untar_path/.git/hooks should exist"


# Test --no-hooks doesn't include hooks
setup
backup --no-hooks
[ ! -d "$untar_path/.git/hooks" ]
assert $? "$LINENO: $untar_path/.git/hooks should not exist"


# Test --branches includes local branches
setup
backup --branches
[ -d "$untar_path/my_branch" ]
assert $? "$LINENO: $untar_path/my_branch should exist"
mkdir "$untar_path/branch_test"
cd "$test_path/remote_project"
git format-patch --output-directory "${untar_path}/branch_test" "master..my_branch" >/dev/null
diff "${untar_path}/branch_test" "$untar_path/my_branch"
assert $? "$LINENO: $untar_path/my_branch should be the same as ${untar_path}/branch_test"


# Test --no-branches includes local branches
setup
backup --no-branches
[ ! -d "$untar_path/my_branch" ]
assert $? "$LINENO: $untar_path/my_branch should not exist"
