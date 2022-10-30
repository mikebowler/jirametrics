# frozen_string_literal: true

class StatusCollection
  def initialize
    @list = []
  end

  def filter_status_names category_name:, including: nil, excluding: nil
    including = expand_statuses including
    excluding = expand_statuses excluding

    @list.collect do |status|
      keep = status.category_name == category_name ||
        including.any? { |s| s.name == status.name }
      keep = false if excluding.any? { |s| s.name == status.name }

      status.name if keep
    end.compact
  end

  def expand_statuses names_or_ids
    result = []
    return result if names_or_ids.nil?

    names_or_ids = [names_or_ids] unless names_or_ids.is_a? Array

    names_or_ids.each do |name_or_id|
      status = @list.find { |s| s.name == name_or_id || s.id == name_or_id }
      result << status unless status.nil?
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

  def print_all
    category_names = @list.collect(&:category_name).uniq.sort.reverse
    category_names.each do |category|
      puts category
      filter_status_names(category_name: category).sort.each do |status_name|
        puts "  #{status_name}"
      end
    end
  end

  def find_by_name name
    find { |status| status.name == name }
  end

  def find(&block)= @list.find(&block)
  def collect(&block) = @list.collect(&block)
  def each(&block) = @list.each(&block)
  def select(&block) = @list.select(&block)
  def <<(arg) = @list << arg
  def empty? = @list.empty?
  def clear = @list.clear
end
