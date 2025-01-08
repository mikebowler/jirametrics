# frozen_string_literal: true

class StatusNotFoundError < StandardError
end

class StatusCollection
  attr_reader :historical_status_mappings

  def initialize
    @list = []
    @historical_status_mappings = {} # 'name:id' => category
  end

  def expand_statuses names_or_ids
    result = []
    return result if names_or_ids.nil?

    names_or_ids = [names_or_ids] unless names_or_ids.is_a? Array

    names_or_ids.each do |name_or_id|
      raise "Baboom: #{name_or_id}" unless name_or_id.is_a? Integer

      status = @list.find { |s| s.name == name_or_id || s.id == name_or_id }
      if status.nil?
        if block_given?
          yield name_or_id
          next
        else
          all_status_names = @list.collect(&:to_s).uniq.sort.join(', ')
          raise StatusNotFoundError, "Status not found: \"#{name_or_id}\". Possible statuses are: #{all_status_names}"
        end
      end

      result << status
    end
    result
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

  # Return the in-progress category or raise an error if we can't find one.
  def in_progress_category
    first_in_progress_status = find { |s| s.category.indeterminate? }
    raise "Can't find even one in-progress status in #{self}" unless first_in_progress_status

    first_in_progress_status.category
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
end
