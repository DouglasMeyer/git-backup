#!/bin/sh
usage_text=<<_END_
Git Restore, a tool to restore from a backup file (using git backup).
Usage: $0 [options...] backup_file [directory]
_END_


### Script Support
    # Exit immediately if a command dosn't exit with 0
        # Exit immediately if a variable isn't defined
set -e -u
on_exit() {
  status=$?

  [ -d "$tmp_dir" ] && rm -rf "$tmp_dir"

  if [ "$status" -ne 0 ] ; then
    echo "Something went wrong in $0"
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
  echo "${usage_text}"
  exit 2
fi


### Script Body
backup_name=$(basename $backup_file)
backup_name=${backup_name%%.*}
backup_path="$(pwd)/${backup_name}"
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

cp .git/config "${backup_path}/.git/config"

cp .git/hooks/* "${backup_path}/.git/hooks/"

branches=$(ls */[0-9][0-9][0-9][0-9]-*.patch | cut -d/ -f1 | sort -u)
for branch in $branches ; do
  cd "$backup_path"
  remote=$(git config --get "branch.${branch}.remote") || true
  merge=$(git config --get "branch.${branch}.merge") || true
  merge=${merge##*/}
  remote_branch="master"
  if [ $remote -a $merge -a "$(git show-ref "${remote}/${merge}")" ] ; then
    remote_branch="${remote}/${merge}"
  fi
  git checkout -b $branch $remote_branch 2>/dev/null
  git am ${tmp_dir}/$branch/*.patch >/dev/null

  git checkout master 2>/dev/null
  cd "$tmp_dir"
done
