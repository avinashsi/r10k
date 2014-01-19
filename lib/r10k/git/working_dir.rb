require 'forwardable'
require 'r10k/logging'
require 'r10k/git'
require 'r10k/git/cache'

# Implements sparse git repositories with shared objects
#
# Working directory instances use the git alternatives object store, so that
# working directories only contain checked out files and all object files are
# shared.
class R10K::Git::WorkingDir < R10K::Git::Repository

  include R10K::Logging

  extend Forwardable

  # @!attribute [r] cache
  #   @return [R10K::Git::Cache] The object cache backing this working directory
  attr_reader :cache

  # @!attribute [r] ref
  #   @return [R10K::Git::Ref] The git reference to use check out in the given directory
  attr_reader :ref

  # @!attribute [r] remote
  #   @return [String] The actual remote used as an upstream for this module.
  attr_reader :remote

  # Create a new shallow git working directory
  #
  # @param ref     [String, R10K::Git::Ref]
  # @param remote  [String]
  # @param basedir [String]
  # @param dirname [String]
  def initialize(ref, remote, basedir, dirname = nil)

    @remote  = remote
    @basedir = basedir
    @dirname = dirname || ref

    @full_path = File.join(@basedir, @dirname)
    @git_dir   = File.join(@full_path, '.git')

    @cache = R10K::Git::Cache.generate(@remote)

    if ref.is_a? String
      @ref = R10K::Git::Ref.new(ref, @cache)
    else
      @ref = ref
    end
  end

  # Synchronize the local git repository.
  def sync
    # TODO stop forcing a sync every time.
    @cache.sync

    if cloned?
      fetch_from_cache
    else
      clone
    end
    checkout(@ref)
  end

  # Determine if repo has been cloned into a specific dir
  #
  # @return [true, false] If the repo has already been cloned
  def cloned?
    File.directory? @git_dir
  end
  alias :git? :cloned?

  # Does a directory exist where we expect a working dir to be?
  # @return [true, false]
  def exist?
    File.directory? @full_path
  end

  private

  def fetch_from_cache
    set_cache_remote
    fetch(:cache)
  end

  def set_cache_remote
    if self.remote != @cache.remote
      git "remote set-url cache #{@cache.git_dir}", :path => @full_path
    end
  end

  # Perform a non-bare clone of a git repository.
  def clone
    # We do the clone against the target repo using the `--reference` flag so
    # that doing a normal `git pull` on a directory will work.
    git "clone --reference #{@cache.git_dir} #{@remote} #{@full_path}"
    git "remote add cache #{@cache.git_dir}", :path => @full_path
    checkout(@ref)
  end

  # check out the given ref
  #
  # @param ref [#to_s] The git reference to check out
  def checkout(ref)
    commit  = @cache.rev_parse(ref)
    current = rev_parse('HEAD')

    if commit == current
      logger.debug1 "Git repo #{@full_path} is already at #{commit}, no need to checkout"
      return
    end

    begin
      git "checkout --force #{commit}", :path => @full_path
    rescue R10K::ExecutionFailure => e
      logger.error "Unable to locate commit object #{commit} in git repo #{@full_path}"
      raise
    end
  end

  private :rev_parse
end
