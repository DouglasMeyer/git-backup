#!/usr/bin/env ruby

require 'tmpdir'
require 'pathname'

class GitBackup
  def self.run
    source = Pathname('.')
    file = Pathname(Dir.pwd).basename.to_s + '.tar'
    show_usage = false
    while arg = ARGV.pop
      case arg
      when "--help", "-h"
        show_usage = true
      else
        puts "Unknown argument #{arg}"
        show_usage = true
      end
    end
    if show_usage
      puts <<-%Q(
Usage:
git-backup file.tar
Creates a backup of the git repo.
If the repo does not have remove branches; git-backup will copy the project, run garbage-collection, capture changes in submodules, then tar the results.
If the repo has remote branches, git-backup will create a tar file with the following contents:
.git/
  config
  hooks/
branch_name/
  patches till they meet a remote branch
cached_changes.patch
changes.patch
untracked.tar
ignored.tar
staged changes
submodule/path/
  same thing as a .git directory
)
exit 0
    end
    Dir.mktmpdir("git-backup#{source.expand_path.to_s.gsub(/\//, '_')}-#{file} ") do |tmpdir|
      puts "Backing-up to #{file}"
      self.new(source, tmpdir)

      %x(cd "#{tmpdir}" && tar cf "#{file}" * .git)
      %x(mv "#{tmpdir}/#{file}" ./)
    end
  end

  def initialize backup_source, tmpdir
    @tmpdir = tmpdir
    Dir.chdir(backup_source) do
      if has_remote?
        backup_configuration
        backup_branches
        backup_cached_changes
        backup_changes
        backup_untracked_files
        backup_ignored_files
        backup_stashes
      else
        backup_project
        garbage_collect
      end
      backup_submodules
    end
  end

  def has_remote?
    git('remote') != ''
  end

  def backup_configuration
    %x(mkdir "#{@tmpdir}/.git")
    %x(cp .git/config "#{@tmpdir}/.git/")
    %x(cp -R .git/hooks "#{@tmpdir}/.git/")
  end

  def backup_branches
    branches = git('branch').map{|name| name[2..-1].strip }.select do |branch_name|
      next if branch_name == '(no branch)'
#FIXME: can there be more than one remote?
      remote = git("config --get \"branch.#{branch_name}.remote\"").strip
      merge = git("config --get \"branch.#{branch_name}.merge\"").strip
      remote_branch = if remote.empty? || merge.empty?
        'master'
      else
        "#{remote}/#{merge.split('/').last}"
      end
      base = git("merge-base #{branch_name} #{remote_branch}").strip
      if !base.empty? && git("rev-parse #{branch_name}") != git("rev-parse #{base}")
        git("format-patch --output-directory \"#{@tmpdir}/#{branch_name}\" #{base}..#{branch_name}")
        true
      else
        false
      end
    end
  end

  def backup_cached_changes
    git "diff --cached --binary > \"#{@tmpdir}/cached_changes.patch\""
    if %x(wc -c "#{@tmpdir}/cached_changes.patch").split(' ').first == '0'
      %x(rm "#{@tmpdir}/cached_changes.patch")
    end
  end

  def backup_changes
    git "diff --binary > \"#{@tmpdir}/changes.patch\""
    if %x(wc -c "#{@tmpdir}/changes.patch").split(' ').first == '0'
      %x(rm "#{@tmpdir}/changes.patch")
    end
  end

  def backup_untracked_files
    files = git('clean --dry-run -d').map{|file| file.sub(/^Would remove /,'').strip }
    %x(tar cf "#{@tmpdir}/untracked.tar" "#{files.join('"  "')}") if files.any?
  end

  def backup_ignored_files
    files = git('clean --dry-run -d -X').map{|file| file.sub(/^Would remove /,'').strip }
    %x(tar cf "#{@tmpdir}/ignored.tar" "#{files.join('"  "')}") if files.any?
  end

  def backup_stashes
    git("stash list").each do |stash_name|
      stash_name.strip!
      git("stash show -p #{stash_name.split(':').first} > \"#{@tmpdir}/#{stash_name.gsub(/\//, "_")}\"")
    end
  end

  def backup_project
    %x(cp -R . "#{@tmpdir}")
  end

  def garbage_collect
    %x(cd "#{@tmpdir}" && git gc --aggressive --prune=today)
  end

  def backup_submodules
    git("submodule").each do |submodule|
      submodule_path = submodule.split(' ')[1]
      submodule_tmp_path = "#{@tmpdir}/#{submodule_path}"
      %x(mkdir -p "#{submodule_tmp_path}")
      self.class.new submodule_path, submodule_tmp_path
#NOTE: I'm assuming if there is only .git/config and .git/hooks/*.sample that nothing has changed.
      if %x(cd "#{submodule_tmp_path}" && find) == %Q(.
./.git
./.git/hooks
./.git/hooks/post-update.sample
./.git/hooks/applypatch-msg.sample
./.git/hooks/pre-applypatch.sample
./.git/hooks/prepare-commit-msg.sample
./.git/hooks/post-commit.sample
./.git/hooks/update.sample
./.git/hooks/pre-commit.sample
./.git/hooks/commit-msg.sample
./.git/hooks/pre-rebase.sample
./.git/hooks/post-receive.sample
./.git/config
)
        FileUtils.remove_entry_secure submodule_tmp_path
        dir = Pathname(submodule_tmp_path) + '..'
        while %x(ls -a "#{dir}") == ".\n..\n"
          Dir.rmdir(dir)
          dir = dir + '..'
        end
      end
    end
  end

  def git command
#puts %Q(git #{command})
    %x(git #{command})
  end

end

GitBackup.run

