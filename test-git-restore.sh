#!/bin/bash

. $(pwd)/test-helper.sh

cd $test_path/local_project
$backup_cmd || error "$LINENO: command failed"
mkdir $test_path/restore
cd $test_path/restore
$restore_cmd ../local_project/local_project.tar || echo "$LINENO: command failed"

cd $test_path/remote_project
$backup_cmd --untracked --ignored || echo "$LINENO: backup failed"
cd $test_path/restore
$restore_cmd ../remote_project/remote_project.tar || echo "$LINENO: restore failed"

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
assert_equal "Not tracked content" "$(cat ./not\ tracked\ 1)"
assert_equal "" "$(git show not\ tracked\ 1)"

# Test ignored files get restored
assert_equal "Ignore me" "$(cat ./ignore\ file\ 1)"
assert_equal "" "$(git show ignore\ file\ 1)"

# Test stashed changes get restored
git stash show -p | grep -q "Stashed content"
assert $? "$LINENO: stashed content should be stashed"
git stash list | grep -q "stash@{0}: On my_branch: My stash"
assert $? "$LINENO: stash should have correct name: $(git stash list)"
