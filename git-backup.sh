#!/bin/sh
usage_text="Git Backup, a tool to backup your git projects and not duplicate what is stored remotely.
Usage: $0 [options...]
Options:

  --no-default         - Don't include default options (needs to be first argument).

  --config (default)   - Include config (./.git/) files in backup.
  --no-config          - Don't include such files in backup.

  --hooks (default)    - Include hooks (./.git/hooks) files in backup.
  --no-hooks

  --branches (default) - Include local branches (upto commits stored remotely).
  --no-branches

  --cached (default)   - Include cached changes in backup.
  --no-cached

  --changes (default)  - Include working directory changes in backup.
  --no-changes"
#TODO: is it possible for --no-default to be specified anywhere?


### Script Support
    # Exit immediately if a command dosn't exit with 0
        # Exit immediately if a variable isn't defined
set -e #-u
on_exit() {
  rm -rf "$tmp_dir"
}
trap on_exit EXIT


### Script Options/Flags/Defaults
usage=
config=t
hooks=t
branches=t
cached=t
changes=t

while [ $# -ne 0 ] ; do
  case $1 in
  --help | --usage ) shift ; usage=t ;;
  --no-default )
    shift
    config=
    hooks=
    branches=
    cached=
    changes=
    ;;
  --config ) shift ; config=t ;;
  --no-config ) shift ; config= ;;
  --hooks ) shift ; hooks=t ;;
  --no-hooks ) shift ; hooks= ;;
  --branches ) shift ; branches=t ;;
  --no-branches ) shift ; branches= ;;
  --cached ) shift ; cached=t ;;
  --no-cached ) shift ; cached= ;;
  --changes ) shift ; changes=t ;;
  --no-changes ) shift ; changes= ;;
  * )
    echo "Unknown option \"$1\""
    echo
    usage=t
    shift
    ;;
  esac
done

if [ $usage ] ; then
  echo "$usage_text"
  exit 2
fi


### Script Body
backup_path=$(pwd)
backup_name=$(basename $backup_path)
tar_file=$backup_name.tar
tmp_dir=$(mktemp --directory --tmpdir tmp.git-backup.$backup_name.XXXXX)

if [ -z "$(git remote)" ] ; then
  #git gc --aggressive #--prune=today
  tar cf "$tmp_dir/$tar_file" .
  mv "$tmp_dir/$tar_file" "$backup_path/$tar_file"
  exit 0
fi

mkdir -p "$tmp_dir/.git"
cp .git/HEAD $tmp_dir/.git/HEAD

if [ $config ] ; then
  cp .git/config "$tmp_dir/.git/"
fi

if [ $hooks ] ; then
  mkdir -p "$tmp_dir/.git"
  cp -r .git/hooks "$tmp_dir/.git/"
fi

if [ $branches ] ; then
  for branch in $(git branch | cut -c 3-) ; do
    remote=$(git config --get "branch.$branch.remote") || true
    merge=$(git config --get "branch.$branch.merge") || true
    merge=${merge##*/}
    remote_branch="master"
    if [ $remote -a $merge -a "$(git show-ref "$remote/$merge")" ] ; then
      remote_branch="$remote/$merge"
    fi
    base=$(git merge-base $branch $remote_branch)
    if [ "$base" != $(git rev-parse $branch) ] ; then
      mkdir -p "$tmp_dir/$branch"
      git format-patch --output-directory "$tmp_dir/$branch" $base..$branch >/dev/null
    fi
  done
fi

if [ $cached ] ; then
  git diff --cached --binary > "$tmp_dir/cached_changes.patch"
fi

if [ $changes ] ; then
  git diff --binary > "$tmp_dir/changes.patch"
fi

pushd "$tmp_dir" > /dev/null
tar cf "$backup_path/$tar_file" .
popd > /dev/null
