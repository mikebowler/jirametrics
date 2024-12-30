# frozen_string_literal: true

require 'jirametrics/value_equality'

class Status
  include ValueEquality
  attr_reader :id, :category_name, :category_id, :category_key, :project_id
  attr_accessor :name

  class Category
    def initialize status
      @status = status
    end

    def name
      @status.category_name
    end

    def id
      @status.category_id
    end

    def key
      @status.category_key
    end

    def to_s
      @status.category_to_s
    end
  end

  def self.from_raw raw
    category_config = raw['statusCategory']

    raise category_config.inspect unless category_config['key']

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
    @category_name = category_name
    @category_id = category_id
    @category_key = category_key
    @project_id = project_id
    @artificial = artificial

    # TODO: This validation still needs to be in place but tests must change first.
    # unless %w[new indeterminate done].include? @category_key
    #   text = "Status() Category key (#{@category_key.inspect}) must be one of new, indeterminate, done"
    #   caller(1..4).each do |line|
    #     text << "\n-> Called from #{line}"
    #   end
    #   puts text
    # end
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

  def category_to_s
    "#{category_name.inspect}:#{category_id.inspect}"
  end

  def artificial?
    @artificial
  end

  def == other
    @id == other.id && @name == other.name && @category_id == other.category_id && @category_name == other.category_name
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

  def category
    Category.new(self)
  end
end
