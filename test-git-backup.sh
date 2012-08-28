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
echo "Ignore me" > ignore_file
echo "ignore_file" > .gitignore
git add .gitignore
echo "First update" > first_file
git add first_file
git commit -m "First update" >/dev/null

git checkout -b my_branch &>/dev/null
echo "A branch" > first_file
git add first_file
git commit -m "A branch" >/dev/null

echo "Stash content" > first_file
git stash save "My stash" >/dev/null

echo "Cached change" > first_file
git add first_file

echo "Working Copy change" > first_file

echo "Not tracked" > not_tracked

setup() {
  rm -rf "$untar_path"
  mkdir "$untar_path"
  cd "$test_path/${1-remote}_project"
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


# Test backup incudes defaults
setup
backup
[ -e "$untar_path/.git/config" ]
assert $? "$LINENO: $untar_path/.git/config should not exist"
[ -d "$untar_path/.git/hooks" ]
assert $? "$LINENO: $untar_path/.git/hooks should not exist"
[ -d "$untar_path/my_branch" ]
assert $? "$LINENO: $untar_path/my_branch should not exist"
[ -f cached_changes.patch ]
assert $? "$LINENO: cached_changes.patch should not exist"
[ -f changes.patch ]
assert $? "$LINENO: changes.patch should exist"
[ ! -f untracked.tar ] ; assert $? "$LINENO: untracked.tar should not exist"
[ ! -f ignored.tar ] ; assert $? "$LINENO: ignored.tar should not exist"
cat "stash@{0}: On my_branch: My stash" | grep -q "diff --git a/first_file"
assert $? "$LINENO: first_file should be stashed"


# Test --no-default doesn't incude defaults
setup
backup --no-default
[ ! -e "$untar_path/.git/config" ]
assert $? "$LINENO: $untar_path/.git/config should not exist"
[ ! -d "$untar_path/.git/hooks" ]
assert $? "$LINENO: $untar_path/.git/hooks should not exist"
[ ! -d "$untar_path/my_branch" ]
assert $? "$LINENO: $untar_path/my_branch should not exist"
[ ! -f cached_changes.patch ]
assert $? "$LINENO: cached_changes.patch should not exist"
[ ! -f changes.patch ]
assert $? "$LINENO: changes.patch should not exist"
[ ! -f untracked.tar ] ; assert $? "$LINENO: untracked.tar should not exist"
[ ! -f ignored.tar ] ; assert $? "$LINENO: ignored.tar should not exist"
[ ! -f stash@{?}:* ]; assert $? "$LINENO: there should be no stahsed changes"


# Test config gets backed-up
setup
backup --config
files_equal "$test_path/remote_project/.git/config" "$untar_path/.git/config"


# Test --no-config doesn't include config
setup
backup --no-config
[ ! -e "$untar_path/.git/config" ]
assert $? "$LINENO: $untar_path/.git/config should not exist"


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


# Test --cached includes cached changes
setup
backup --cached
[ -f .git/HEAD ]
assert $? "$LINENO: the HEAD should be tracked"
assert_equal "ref: refs/heads/my_branch" "$(cat .git/HEAD)"
cat cached_changes.patch | grep -q "diff --git a/first_file"
assert $? "$LINENO: first_file should be cached"


# Test --no-cached does not include cached changes
setup
backup --no-cached
[ ! -f cached_changes.patch ]
assert $? "$LINENO: cached_changes.patch should not exist"


# Test --changes should include working directory changes
setup
backup --changes
cat changes.patch | grep -q "diff --git a/first_file"
assert $? "$LINENO: first_file should be cached"


# Test --no-changes should not include working directory changes
setup
backup --no-changes
[ ! -f changes.patch ]
assert $? "$LINENO: changes.patch should not exist"


# Test --untracked should include untracked files
setup
backup --untracked
cd "$test_path/remote_project"
tar cf untracked.tar not_tracked
mv untracked.tar ..
files_equal "$test_path/untracked.tar" "$untar_path/untracked.tar"


# Test --no-untracked should not include untracked files
setup
backup --no-untracked
[ ! -f untracked.tar ] ; assert $? "$LINENO: untracked.tar should not exist"


# Test --ignored should include files ignored by git
setup
backup --ignored
cd "$test_path/remote_project"
tar cf ignored.tar ignore_file
mv ignored.tar ..
files_equal "$test_path/ignored.tar" "$untar_path/ignored.tar"


# Test --no-ignored should not include files ignored by git
setup
backup --no-ignored
[ ! -f ignored.tar ] ; assert $? "$LINENO: ignored.tar should not exist"


# Test --stashes should include git stashes
setup
backup --stashes
cat "stash@{0}: On my_branch: My stash" | grep -q "diff --git a/first_file"
assert $? "$LINENO: first_file should be stashed"


# Test --no-stashes should include git stashes
setup
backup --no-stashes
[ ! -f stash@{?}:* ]; assert $? "$LINENO: there should be no stahsed changes"
