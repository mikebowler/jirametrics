# frozen_string_literal: true

require 'jirametrics/value_equality'

class Status
  attr_reader :id, :project_id, :category
  attr_accessor :name

  class Category
    attr_reader :id, :name, :key

    def initialize id:, name:, key:
      @id = id
      @name = name
      @key = key
    end

    def to_s
      "#{name.inspect}:#{id.inspect}"
    end

    def <=> other
      id <=> other.id
    end

    def == other
      id == other.id
    end

    def eql?(other) = id.eql?(other.id)
    def hash = id.hash

    def new? = (@key == 'new')
    def indeterminate? = (@key == 'indeterminate')
    def done? = (@key == 'done')
  end

  def self.from_raw raw
    raise "raw cannot be nil" if raw.nil?

    category_config = raw['statusCategory']
    raise "statusCategory can't be nil in #{category_config.inspect}" if category_config.nil?

    Status.new(
      name: raw['name'],
      id: raw['id'].to_i,
      category_name: category_config['name'],
      category_id: category_config['id'].to_i,
      category_key: category_config['key'],
      project_id: raw['scope']&.[]('project')&.[]('id'),
      artificial: false
    )
  end

  def initialize name:, id:, category_name:, category_id:, category_key:, project_id: nil, artificial: true
    # These checks are needed because nils used to be possible and now they aren't.
    raise 'id cannot be nil' if id.nil?
    raise 'category_id cannot be nil' if category_id.nil?

    @name = name
    @id = id
    @category = Category.new id: category_id, name: category_name, key: category_key
    @project_id = project_id
    @artificial = artificial
  end

  def project_scoped?
    !!@project_id
  end

  def global?
    !project_scoped?
  end

  def to_s
    "#{name.inspect}:#{id.inspect}"
  end

  def artificial?
    @artificial
  end

  def == other
    return false unless other.is_a? Status

    @id == other.id && @name == other.name && @category.id == other.category.id && @category.name == other.category.name
  end

  def eql?(other)
    self == other
  end

  def <=> other
    result = @name.casecmp(other.name)
    result = @id <=> other.id if result.zero?
    result
  end

  def inspect
    result = []
    result << "Status(name: #{@name.inspect}"
    result << "id: #{@id.inspect}"
    result << "project_id: #{@project_id}" if @project_id
    category = self.category
    result << "category: {name:#{category.name.inspect}, id: #{category.id.inspect}, key: #{category.key.inspect}}"
    result << 'artificial' if artificial?
    result.join(', ') << ')'
  end

  def value_equality_ignored_variables
    [:@raw]
  end
end
