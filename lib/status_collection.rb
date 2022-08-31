# frozen_string_literal: true

class StatusCollection #< Array
  def initialize
    @list = []
  end

  def filtered_status_names category_name
    puts "Deprecated: StatusCollection.filtered_status_names(#{category_name})"
    @list.collect do |status|
      next unless status.category_name == category_name

      status.name
    end.compact
  end

  def todo_status_names = filtered_status_names('To Do')
  def in_progress_status_names = filtered_status_names('In Progress')
  def done_status_names = filtered_status_names('Done')

  ##############

  def filter_status_names category_name:, including:, excluding:
    including = [] if including.nil?
    excluding = [] if excluding.nil?
    including = [including] unless including.is_a? Array
    excluding = [excluding] unless excluding.is_a? Array

    @list.collect do |status|
      keep = status.category_name == category_name || matches?(list: including, status: status)
      keep = false if matches?(list: excluding, status: status)

      status.name if keep
    end.compact
  end

  def matches? list:, status:
    list.include?(status.name) || list.include?(status.id)
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
      filtered_status_names(category).sort.each do |status_name|
        puts "  #{status_name}"
      end
    end
  end

  def find(&block)= @list.find(&block)
  def collect(&block) = @list.collect(&block)
  def each(&block) = @list.each(&block)
  def select(&block) = @list.select(&block)
  def <<(arg) = @list << arg
  def empty? = @list.empty?
end
