# frozen_string_literal: true

require 'jirametrics/value_equality'

class Status
  include ValueEquality
  attr_reader :id, :category_name, :category_id, :project_id
  attr_accessor :name

  def self.from_raw raw
    category_config = raw['statusCategory']

    Status.new(
      name: raw['name'],
      id: raw['id'].to_i,
      category_name: category_config['name'],
      category_id: category_config['id'].to_i,
      project_id: raw['scope']&.[]('project')&.[]('id'),
      artificial: false
    )
  end

  def initialize name:, id:, category_name:, category_id:, project_id: nil, artificial: true
    # These checks are needed because nils used to be possible and now they aren't.
    raise 'id cannot be nil' if id.nil?
    raise 'category_id cannot be nil' if category_id.nil?

    @name = name
    @id = id
    @category_name = category_name
    @category_id = category_id
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
    @id == other.id && @name == other.name && @category_id == other.category_id && @category_name == other.category_name
  end

  def inspect
    result = []
    result << "Status(name: #{@name.inspect}"
    result << "id: #{@id.inspect}" if @id
    result << "category_name: #{@category_name.inspect}"
    result << "category_id: #{@category_id.inspect}" if @category_id
    result << "project_id: #{@project_id}" if @project_id
    result << 'artificial' if artificial?
    result.join(', ') << ')'
  end

  def value_equality_ignored_variables
    [:@raw]
  end
end
