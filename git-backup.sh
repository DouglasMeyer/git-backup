#!/bin/sh
usage_text="Git Backup, a tool to backup your git projects and not duplicate what is stored remotely.
Usage: $0 [options...]
Options:

  --no-default         - Don't include default options.
  --all                - Will turn on all options.

  --config (default)   - Include config (./.git/) files in backup.
  --no-config          - Don't include such files in backup.

  --hooks (default)    - Include hooks (./.git/hooks) files in backup.
  --no-hooks

  --branches (default) - Include local branches (upto commits stored remotely).
  --no-branches

  --staches (default)  - Include stashed changes in backup.
  --no-staches

  --cached (default)   - Include cached changes in backup.
  --no-cached

  --changes (default)  - Include working directory changes in backup.
  --no-changes

  --untracked          - Include untracked files in backup.
  --no-untracked (default)

  --ignored            - Include ignored files in backup.
  --no-ignored (default)"
#TODO: is it possible for --no-default to be specified anywhere?
#NOTE: do I want to backup submodule changes? I'm thinking no, because it is
#      its own git project/directory.


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
config=
hooks=
branches=
stashes=
cached=
changes=
untracked=
ignored=
if [[ $* != *--no-default* ]] ; then
  config=t
  hooks=t
  branches=t
  stashes=t
  cached=t
  changes=t
fi

while [ $# -ne 0 ] ; do
  case $1 in
  --help | --usage ) shift ; usage=t ;;
  --no-default ) shift ;;
  --all ) shift
    config=t
    hooks=t
    branches=t
    stashes=t
    cached=t
    changes=t
    untracked=t
    ignored=t
    ;;
  --config ) shift ; config=t ;;
  --no-config ) shift ; config= ;;
  --hooks ) shift ; hooks=t ;;
  --no-hooks ) shift ; hooks= ;;
  --branches ) shift ; branches=t ;;
  --no-branches ) shift ; branches= ;;
  --stashes ) shift ; stashes=t ;;
  --no-stashes ) shift ; stashes= ;;
  --cached ) shift ; cached=t ;;
  --no-cached ) shift ; cached= ;;
  --changes ) shift ; changes=t ;;
  --no-changes ) shift ; changes= ;;
  --untracked ) shift ; untracked=t ;;
  --no-untracked ) shift ; untracked= ;;
  --ignored ) shift ; ignored=t ;;
  --no-ignored ) shift ; ignored= ;;
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
  #git gc --aggressive #--prune=today #TODO: how much space can we save?
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

if [ $stashes ] ; then
  for stash in "$(git stash list)" ; do
    git stash show -p "${stash%%:*}" > $tmp_dir/${stash/\//_}
  done
fi

if [ $cached ] ; then
  git diff --cached --binary > "$tmp_dir/cached_changes.patch"
  if [ -z "$(cat $tmp_dir/cached_changes.patch)" ] ; then
    rm $tmp_dir/cached_changes.patch
  fi
fi

if [ $changes ] ; then
  git diff --binary > "$tmp_dir/changes.patch"
  if [ -z "$(cat $tmp_dir/changes.patch)" ] ; then
    rm $tmp_dir/changes.patch
  fi
fi

if [ $untracked ] ; then
  untracked_files=$(git clean --dry-run -d | sed "s/^Would remove //")
  if [ $untracked_files ] ; then
    tar cf $tmp_dir/untracked.tar $untracked_files
  fi
fi

if [ $ignored ] ; then
  ignored_files=$(git clean --dry-run -d -X | sed "s/^Would remove //")
  if [ $ignored_files ] ; then
    tar cf $tmp_dir/ignored.tar $ignored_files
  fi
fi

pushd "$tmp_dir" > /dev/null
tar cf "$backup_path/$tar_file" .
popd > /dev/null
