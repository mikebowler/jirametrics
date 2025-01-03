# frozen_string_literal: true

class StatusNotFoundError < StandardError
end

class StatusCollection
  def initialize
    @list = []
  end

  def filter_status_names category_name:, including: nil, excluding: nil
    including = expand_statuses including
    excluding = expand_statuses excluding

    @list.filter_map do |status|
      keep = status.category.name == category_name ||
        including.any? { |s| s.name == status.name }
      keep = false if excluding.any? { |s| s.name == status.name }

      status.name if keep
    end
  end

  def expand_statuses names_or_ids
    result = []
    return result if names_or_ids.nil?

    names_or_ids = [names_or_ids] unless names_or_ids.is_a? Array

    names_or_ids.each do |name_or_id|
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

  def todo including: nil, excluding: nil
    filter_status_names category_name: 'To Do', including: including, excluding: excluding
  end

  def in_progress including: nil, excluding: nil
    filter_status_names category_name: 'In Progress', including: including, excluding: excluding
  end

  def done including: nil, excluding: nil
    filter_status_names category_name: 'Done', including: including, excluding: excluding
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
end
