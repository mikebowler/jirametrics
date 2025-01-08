# frozen_string_literal: true

class StatusNotFoundError < StandardError
end

class StatusCollection
  attr_reader :historical_status_mappings

  def initialize
    @list = []
    @historical_status_mappings = {} # 'name:id' => category
  end

  # Return the status matching this id or nil if it can't be found.
  def find_by_id id
    @list.find { |status| status.id == id }
  end

  def find_all_by_name name
    @list.select { |status| status.name == name }
  end

  def find_all_categories
    @list
      .collect(&:category)
      .uniq
      .sort_by(&:id)
  end

  def find_all_categories_by_name name
    @list
      .select { |s| s.category.name == name }
      .collect(&:category)
      .uniq
      .sort_by(&:id)
  end

  def collect(&block) = @list.collect(&block)
  def find(&block) = @list.find(&block)
  def each(&block) = @list.each(&block)
  def select(&block) = @list.select(&block)
  def <<(arg) = @list << arg
  def empty? = @list.empty?
  def clear = @list.clear
  def delete(object) = @list.delete(object)

  def to_s
    "[#{@list.join(', ')}]"
  end

  def inspect
    "StatusCollection#{self}"
  end

  def fabricate_status_for id:, name:
    category = @historical_status_mappings["#{name.inspect}:#{id.inspect}"]
    category = in_progress_category if category.nil?

    status = Status.new(
      name: name,
      id: id,
      category_name: category.name,
      category_id: category.id,
      category_key: category.key,
      artificial: true
    )
    @list << status
    status
  end

  private

  # Return the in-progress category or raise an error if we can't find one.
  def in_progress_category
    first_in_progress_status = find { |s| s.category.indeterminate? }
    raise "Can't find even one in-progress status in #{self}" unless first_in_progress_status

    first_in_progress_status.category
  end
end
