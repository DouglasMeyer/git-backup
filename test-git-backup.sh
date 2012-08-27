#!/bin/sh

on_exit() {
  # clean test files
  rm -rf "$build_path"

  # print counts
  echo "$assertions assertions, $failures failures."
}
trap on_exit EXIT

assertions=0
failures=0
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
  assert $? "${2#$build_path/} was not equal to ${1#$build_path/}"
}
backup_cmd=$(pwd)/git-backup.sh

# build test project
build_path=$(mktemp --directory --tmpdir tmp.git-backup.test.XXXXX)
output_path="$build_path/output"

cd "$build_path"
mkdir local_project
cd local_project
git init >/dev/null
echo "First content" > first_file
git add first_file
git commit -m "First commit" >/dev/null

cd "$build_path"
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
  rm -rf "$output_path"
  cd "$build_path/${1-remote}_project"
  mkdir "$output_path"
}


# Test non-remote backup
setup 'local'
$backup_cmd
mv "$build_path/local_project/local_project.tar" "$build_path/local_project.tar"
tar cf "$build_path/tar_project.tar" .
cd "$build_path"
files_equal "$build_path/tar_project.tar" "$build_path/local_project.tar"


# Test config gets backed-up
setup
$backup_cmd
cd "$output_path"
tar xvf ../remote_project/remote_project.tar >/dev/null
files_equal "$build_path/remote_project/.git/config" "$output_path/.git/config"


# Test --no-config doesn't include config
setup
$backup_cmd --no-config
cd "$output_path"
tar xvf ../remote_project/remote_project.tar >/dev/null
[ ! -e "$output_path/.git/config" ]
assert $? "$LINENO: $output_path/.git/config should not exist"


# Test --no-default doesn't incude defaults
setup
$backup_cmd --no-default
cd "$output_path"
tar xvf ../remote_project/remote_project.tar >/dev/null
[ ! -e "$output_path/.git/config" ]
assert $? "$LINENO: $output_path/.git/config should not exist"
[ ! -d "$output_path/.git/hooks" ]
assert $? "$LINENO: $output_path/.git/hooks should not exist"
[ -d "$output_path/my_branch" ]
assert $? "$LINENO: $output_path/my_branch should exist"


# Test --hooks includes hooks
setup
$backup_cmd --hooks
cd "$output_path"
tar xvf ../remote_project/remote_project.tar >/dev/null
[ -e "$output_path/.git/hooks" ]
assert $? "$LINENO: $output_path/.git/hooks should exist"


# Test --no-hooks doesn't include hooks
setup
$backup_cmd --no-hooks
cd "$output_path"
tar xvf ../remote_project/remote_project.tar >/dev/null
[ ! -d "$output_path/.git/hooks" ]
assert $? "$LINENO: $output_path/.git/hooks should not exist"


# Test --branches includes local branches
setup
$backup_cmd --branches
cd "$output_path"
tar xvf ../remote_project/remote_project.tar >/dev/null
[ -d "$output_path/my_branch" ]
assert $? "$LINENO: $output_path/my_branch should exist"
mkdir "$output_path/branch_test"
cd "$build_path/remote_project"
git format-patch --output-directory "${output_path}/branch_test" "master..my_branch" >/dev/null
diff "${output_path}/branch_test" "$output_path/my_branch"
assert $? "$LINENO: $output_path/my_branch should be the same as ${output_path}/branch_test"


# Test --no-branches includes local branches
setup
$backup_cmd --no-branches
cd "$output_path"
tar xvf ../remote_project/remote_project.tar >/dev/null
[ ! -d "$output_path/my_branch" ]
assert $? "$LINENO: $output_path/my_branch should not exist"


[ $failures -eq 0 ]
exit $?
