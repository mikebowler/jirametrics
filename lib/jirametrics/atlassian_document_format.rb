# frozen_string_literal: true

class AtlassianDocumentFormat
  attr_reader :users

  def initialize users:
    @users = users
  end

  def to_html input
    if input.is_a? String
      input
        .gsub(/{color:(#\w{6})}([^{]+){color}/, '<span style="color: \1">\2</span>') # Colours
        .gsub(/\[~accountid:([^\]]+)\]/) { expand_account_id $1 } # Tagged people
        .gsub(/\[([^\|]+)\|(https?[^\]]+)\]/, '<a href="\2">\1</a>') # URLs
        .gsub("\n", '<br />')
    else
      input['content'].collect { |element| adf_node_to_html element }.join("\n")
    end
  end

  # ADF is Atlassian Document Format
  # https://developer.atlassian.com/cloud/jira/platform/apis/document/structure/
  def adf_node_to_html node
    closing_tag = nil
    result = +''
    case node['type']
    when 'paragraph'
      result << '<p>'
      closing_tag = '</p>'
    when 'text'
      marks = adf_marks_to_html node['marks']
      result << marks.collect(&:first).join
      result << node['text']
      result << marks.collect(&:last).join
    when 'bulletList'
      result << '<ul>'
      closing_tag = '</ul>'
    when 'orderedList'
      result << '<ol>'
      closing_tag = '</ol>'
    when 'listItem'
      result << '<li>'
      closing_tag = '</li>'
    when 'table'
      result << '<table>'
      closing_tag = '</table>'
    when 'tableRow'
      result << '<tr>'
      closing_tag = '</tr>'
    when 'tableCell'
      result << '<td>'
      closing_tag = '</td>'
    when 'tableHeader'
      result << '<th>'
      closing_tag = '</th>'
    when 'mention'
      user = node['attrs']['text']
      result << "<b>#{user}</b>"
    when 'taskList'
      result << "<ul class='taskList'>"
      closing_tag = '</ul>'
    when 'taskItem'
      state = node['attrs']['state'] == 'TODO' ? '☐' : '☑'
      result << "<li>#{state} "
      closing_tag = '</li>'
    when 'emoji'
      result << node['attrs']['text']
    else
      result << "<p>Unparseable section: #{node['type']}</p>"
    end

    node['content']&.each do |child|
      result << adf_node_to_html(child)
    end

    result << closing_tag if closing_tag
    result
  end

  def adf_marks_to_html list
    return [] if list.nil?

    mappings = [
      ['strong', '<b>', '</b>'],
      ['code', '<code>', '</code>'],
      ['em', '<em>', '</em>'],
      ['strike', '<s>', '</s>'],
      ['underline', '<u>', '</u>']
    ]

    list.filter_map do |mark|
      type = mark['type']
      if type == 'textColor'
        color = mark['attrs']['color']
        ["<span style='color: #{color}'>", '</span>']
      elsif type == 'link'
        href = mark['attrs']['href']
        title = mark['attrs']['title']
        ["<a href='#{href}' title='#{title}'>", '</a>']
      else
        line = mappings.find { |key, _open, _close| key == type }
        [line[1], line[2]] if line
      end
    end
  end

  def expand_account_id account_id
    user = @users.find { |u| u.account_id == account_id }
    text = account_id
    text = "@#{user.display_name}" if user
    "<span class='account_id'>#{text}</span>"
  end
end