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

  def initialize name: nil, id: nil, category_name: nil, category_id: nil, project_id: nil, artificial: true
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
    "#{name.inspect}:#{id}"
  end

  def artificial?
    @artificial
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
