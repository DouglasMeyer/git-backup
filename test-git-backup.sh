#!/bin/sh

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
mkdir my_project
cd my_project
git init >/dev/null
echo "First content" > first_file
git add first_file
git commit -m "First commit" >/dev/null

setup() {
  rm -rf "$output_path"
  cd "$build_path/my_project"
  mkdir "$output_path"
}


# Test config gets backed-up
setup
$backup_cmd
cd "$output_path"
tar xvf ../my_project/my_project.tar >/dev/null
files_equal "$build_path/my_project/.git/config" "$output_path/.git/config"


# Test --no-config doesn't include config
setup
$backup_cmd --no-config
cd "$output_path"
tar xvf ../my_project/my_project.tar >/dev/null
[ ! -e "$output_path/.git/config" ]
assert $? "$LINENO: $output_path/.git/config should not exist"


# Test --no-default doesn't incude defaults
setup
$backup_cmd --no-default
cd "$output_path"
tar xvf ../my_project/my_project.tar >/dev/null
[ ! -e "$output_path/.git/config" ]
assert $? "$LINENO: $output_path/.git/config should not exist"
[ ! -d "$output_path/.git/hooks" ]
assert $? "$LINENO: $output_path/.git/hooks should not exist"


# Test --hooks includes hooks
setup
$backup_cmd --hooks
cd "$output_path"
tar xvf ../my_project/my_project.tar >/dev/null
[ -e "$output_path/.git/hooks" ]
assert $? "$LINENO: $output_path/.git/hooks should exist"


# Test --no-hooks doesn't include hooks
setup
$backup_cmd --no-hooks
cd "$output_path"
tar xvf ../my_project/my_project.tar >/dev/null
[ ! -d "$output_path/.git/hooks" ]
assert $? "$LINENO: $output_path/.git/hooks should not exist"


# clean test files
rm -rf "$build_path"

# print counts
echo "$assertions assertions, $failures failures."

[ $failures -eq 0 ]
exit $?
