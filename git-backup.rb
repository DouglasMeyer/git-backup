#!/usr/bin/env ruby

require 'tmpdir'
require 'pathname'

class GitBackup
  DefaultOptions = {
    :config     => true,
    :hooks      => true,
    :branches   => true,
    :cahced     => true,
    :changes    => true,
    :untracked  => false,
    :ignored    => false,
    :stashed    => true,
    :submodules => false
  }
  Usage = %Q|
Usage:
git-backup [file.tar]
Creates a backup of the git repo.
If the repo does not have remove branches; git-backup will copy the project, run garbage-collection, capture changes in submodules, then tar the results.
If the repo has remote branches, git-backup will create a tar file with the following contents:
.git/
  config
  hooks/              (skip with --skip-hooks)
branch_name/          (skip with --skip-branches)
  patches till they meet with a remote branch
cached_changes.patch  (skip with --skip-cached)
changes.patch         (skip with --skip-changes)
untracked.tar         (skipped by default, include with --untracked)
ignored.tar           (skipped by default, include with --ignored)
stashed changes       (skip with --skip-stashed)
submodule/path/       (skipped by default, include with --submodules)
  same thing as a .git directory

--all will include all changes.
|
  def self.run
    source = Pathname('.')
    file = Pathname(Dir.pwd).basename.to_s + '.tar'
    file = ARGV.pop if ARGV.length > 0 && !(ARGV.last =~ /^-/)
    file = Pathname(file)
    show_usage = false
    options = DefaultOptions
    while arg = ARGV.pop
      key = arg.sub(/--(skip-)?/,'').to_sym
      if %w(--help -h).include? arg
        show_usage = true
      elsif options.keys.include?(key)
        if arg =~ /^--skip/
          options[key] = false
        else
          options[key] = true
        end
      elsif arg == '--all'
        options.keys.each { |key| options[key] = true }
      else
        puts "Unknown argument #{arg}"
        show_usage = true
      end
    end
    if show_usage
      puts Usage
      exit 0
    end
    Dir.mktmpdir("git-backup#{source.expand_path.to_s.gsub(/\//, '_')} ") do |tmpdir|
      puts "Backing-up to #{file.basename}"
      self.new(source, tmpdir, options)

      %x(cd "#{tmpdir}" && tar cf tmp.tar * .git)
      %x(mv "#{tmpdir}/tmp.tar" "#{file}")
    end
  end

  def initialize backup_source, tmpdir, options
    @tmpdir = tmpdir
    @options = options
    Dir.chdir(backup_source) do
      if has_remote?
        backup_configuration
        backup_hooks            if options[:hooks]
        backup_branches         if options[:branches]
        backup_cached_changes   if options[:cached]
        backup_changes          if options[:changes]
        backup_untracked_files  if options[:untracked]
        backup_ignored_files    if options[:ignored]
        backup_stashes          if options[:stashed]
      else
        backup_project
        garbage_collect
      end
      backup_submodules         if options[:submodules]
    end
  end

  def has_remote?
    git('remote') != ''
  end

  def backup_configuration
    %x(mkdir -p "#{@tmpdir}/.git")
    %x(cp .git/config "#{@tmpdir}/.git/")
  end

  def backup_hooks
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
      self.class.new submodule_path, submodule_tmp_path, @options
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

