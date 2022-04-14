# frozen_string_literal: true

class Status
  attr_reader :id, :type, :category_name, :category_id
  attr_accessor :name

  def initialize name:, id:, category_name:, category_id:
    @name = name
    @id = id
    @category_name = category_name
    @category_id = category_id
  end

  def to_s
    "Status(name=#{@name.inspect}, id=#{@id.inspect}," \
      " category_name=#{@category_name.inspect}, category_id=#{@category_id.inspect})"
  end
end