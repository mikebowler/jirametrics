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
      keep = status.category_name == category_name ||
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
          all_status_names = @list.collect { |s| "#{s.name.inspect}:#{s.id.inspect}" }.uniq.sort.join(', ')
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

  def find id
    @list.find { |status| status.id == id }
  end

  def find_all_by_name name
    @list.select { |status| status.name == name }
  end

  def find_category_id_by_name name
    id = @list.find { |status| status.category_name == name }&.category_id
    unless id
      set = Set.new
      @list.each do |status|
        set << "#{status.category_name.inspect}:#{status.category_id}"
      end
      raise "Unable to find status category #{name.inspect} in [#{set.to_a.sort.join(', ')}]"
    end
    id
  end

  def collect(&block) = @list.collect(&block)
  def each(&block) = @list.each(&block)
  def select(&block) = @list.select(&block)
  def <<(arg) = @list << arg
  def empty? = @list.empty?
  def clear = @list.clear
  def delete(object) = @list.delete(object)

  def inspect
    "StatusCollection(#{@list.join(', ')})"
  end
end
