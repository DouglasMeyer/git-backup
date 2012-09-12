#!/bin/sh
# Copyright (c) 2012, Douglas Meyer

usage_text="Git Restore, a tool to restore from a backup file (using git backup).
Usage: $0 backup_file"


### Script Support
    # Exit immediately if a command dosn't exit with 0
        # Exit immediately if a variable isn't defined
set -e -u
on_exit() {
  if [ -d "$tmp_dir" ] ; then
    rm -rf "$tmp_dir"
  fi
}
trap on_exit EXIT


### Script Options/Flags/Defaults
backup_file=
usage=

while [ $# -ne 0 ] ; do
  case $1 in
  --help | --usage ) shift ; usage=t ;;
  * )
    if [ -z "$backup_file" -a -f "$1" ] ; then
      backup_file=$(realpath "$1") ; shift
    else
      echo "Unknown option \"$1\""
      echo
      usage=t
      shift
    fi
    ;;
  esac
done

if [ "$usage" ] ; then
  echo "$usage_text"
  exit 2
fi


### Script Body
backup_name=$(basename $backup_file)
backup_name=${backup_name%%.*}
backup_path="$(pwd)/$backup_name"
tmp_dir=$(mktemp --directory --tmpdir tmp.git-backup.$backup_name.XXXXX)

cd "$tmp_dir"
tar xvf "$backup_file" >/dev/null

# "Tar"ed git project (no remote backup)
if [ -d .git/objects ] ; then
  mv "$tmp_dir" "$backup_path"
  exit 0
fi

master_remote=$(git config --get "branch.master.remote")
remote_url=$(git config --get "remote.$master_remote.url")
git clone $remote_url "$backup_path" >/dev/null

current_branch="$(cat .git/HEAD)"
current_branch=${current_branch##*/}
cp .git/config "$backup_path/.git/config"

cp .git/hooks/* "$backup_path/.git/hooks/"

branches=$(ls */[0-9][0-9][0-9][0-9]-*.patch | cut -d/ -f1 | sort -u)
for branch in $branches ; do
  cd "$backup_path"
  remote=$(git config --get "branch.$branch.remote") || true
  merge=$(git config --get "branch.$branch.merge") || true
  merge=${merge##*/}
  base=$(cat $tmp_dir/$branch/BASE)
  remote_branch="master"
  if [ $remote -a $merge -a "$(git show-ref "$remote/$merge")" ] ; then
    remote_branch="$remote/$merge"
  fi
  if git rev-parse $branch &>/dev/null ; then
    git checkout $branch 2>/dev/null
  else
    git checkout -b $branch $remote_branch 2>/dev/null
  fi
  git reset --hard $base >/dev/null
  git am --committer-date-is-author-date $tmp_dir/$branch/*.patch >/dev/null

  git checkout master &>/dev/null
  cd "$tmp_dir"
done

for stash in stash@{?}:\ * ; do
  key=${stash%%:*}
  parent=$(cat "$tmp_dir/$key:REF_PARENT")
  name=${stash##*: }
  branch=$(echo $stash | sed "s/^.*: On \([^:]\+\): .*$/\1/")
  cd "$backup_path"
  branch_rev=$(git rev-parse $branch)
  if [ "$branch_rev" ] ; then
    git checkout $branch 2>/dev/null
    git reset --hard $parent >/dev/null
  else
    git checkout -b $branch $parent 2>/dev/null
  fi
  git apply --index --apply "$tmp_dir/$stash"
  git stash save "$name" >/dev/null
  if [ "$branch_rev" ] ; then
    git reset --hard $branch_rev >/dev/null
  else
    git branch -d $branch
  fi
  cd "$tmp_dir"
done

cd "$backup_path"
git checkout $current_branch 2>/dev/null
cd "$tmp_dir"

if [ -f cached_changes.patch ] ; then
  cd "$backup_path"
  git apply --index --apply "$tmp_dir/cached_changes.patch"
  cd "$tmp_dir"
fi

if [ -f changes.patch ] ; then
  cd "$backup_path"
  git apply $tmp_dir/changes.patch
  cd "$tmp_dir"
fi

if [ -f untracked.tar ] ; then
  cd "$backup_path"
  tar xvf $tmp_dir/untracked.tar >/dev/null
  cd "$tmp_dir"
fi

if [ -f ignored.tar ] ; then
  cd "$backup_path"
  tar xvf $tmp_dir/ignored.tar >/dev/null
  cd "$tmp_dir"
fi
