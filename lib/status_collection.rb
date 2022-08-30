# frozen_string_literal: true

class StatusCollection < Array
  def filtered_status_names category_name
    collect do |status|
      next unless status.category_name == category_name

      status.name
    end.compact
  end

  def todo_status_names = filtered_status_names('To Do')
  def in_progress_status_names = filtered_status_names('In Progress')
  def done_status_names = filtered_status_names('Done')

  def print_all
    category_names = collect(&:category_name).uniq.sort.reverse
    category_names.each do |category|
      puts category
      filtered_status_names(category).sort.each do |status_name|
        puts "  #{status_name}"
      end
    end
  end
end
