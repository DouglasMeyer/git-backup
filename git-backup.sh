#!/bin/sh

    # Exit immediately if a command dosn't exit with 0
        # Exit immediately if a variable isn't defined
set -e #-u

usage() {
  echo "Git Backup, a tool to backup your git projects and not duplicate what is stored remotely."
  echo "Usage: $0 [options...]"
  echo "Options:"

  echo "  --no-default       - Don't include default options (needs to be first argument)."

  echo "  --config (default) - Include config (./.git/) files in backup."
  echo "  --no-config        - Don't include such files in backup."

  echo "  --hooks (default)  - Include hooks (./.git/hooks) files in backup."
#  echo "  --no-config        - Don't include such files in backup."
}

usage=
config=t
hooks=t

while [ $# -ne 0 ] ; do
  case $1 in
  --help | --usage ) shift ; usage=t ;;
  --no-default )
    shift
    config=
    hooks=
    ;;
  --config ) shift ; config=t ;;
  --no-config ) shift ; config= ;;
  --hooks ) shift ; hooks=t ;;
  --no-hooks ) shift ; hooks= ;;
  * )
    echo "Unknown option \"$1\""
    echo
    usage=t
    shift
    ;;
  esac
done

if [ $usage ] ; then
  usage
  exit 2
fi

backup_path=$(pwd)
backup_name=$(basename $backup_path)
tar_file=${backup_name}.tar
tmp_dir=$(mktemp --directory --tmpdir tmp.git-backup.$backup_name.XXXXX)

if [ $config ] ; then
  mkdir -p "$tmp_dir/.git"
  cp .git/config "$tmp_dir/.git/"
fi

if [ $hooks ] ; then
  mkdir -p "$tmp_dir/.git"
  cp -r .git/hooks "$tmp_dir/.git/"
fi

pushd "$tmp_dir" > /dev/null
tar cf "$backup_path/$tar_file" .
popd > /dev/null

#TODO: This should be called even if the script fails
rm -rf "$tmp_dir"