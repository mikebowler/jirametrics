# frozen_string_literal: true

class AtlassianDocumentFormat
  attr_reader :users

  def initialize users:, timezone_offset:
    @users = users
    @timezone_offset = timezone_offset
  end

  def to_html input
    if input.is_a? String
      input
        .gsub(/{color:(#\w{6})}([^{]+){color}/, '<span style="color: \1">\2</span>') # Colours
        .gsub(/\[~accountid:([^\]]+)\]/) { expand_account_id $1 } # Tagged people
        .gsub(/\[([^\|]+)\|(https?[^\]]+)\]/, '<a href="\2">\1</a>') # URLs
        .gsub("\n", '<br />')
    elsif input['content']
      input['content'].collect { |element| adf_node_to_html element }.join("\n")
    else
      # We have an actual ADF document with no content.
      ''
    end
  end

  # ADF is Atlassian Document Format
  # https://developer.atlassian.com/cloud/jira/platform/apis/document/structure/
  def adf_node_to_html node # rubocop:disable Metrics/CyclomaticComplexity
    closing_tag = nil
    node_attrs = node['attrs']

    result = +''
    case node['type']
    when 'blockquote'
      result << '<blockquote>'
      closing_tag = '</blockquote>'
    when 'bulletList'
      result << '<ul>'
      closing_tag = '</ul>'
    when 'codeBlock'
      result << '<code>'
      closing_tag = '</code>'
    when 'date'
      result << Time.at(node_attrs['timestamp'].to_i / 1000, in: @timezone_offset).to_date.to_s
    when 'decisionItem'
      result << '<li>'
      closing_tag = '</li>'
    when 'decisionList'
      result << '<div>Decisions<ul>'
      closing_tag = '</ul></div>'
    when 'emoji'
      result << node_attrs['text']
    when 'expand'
      # TODO: Maybe, someday, make this actually expandable. For now it's always open
      result << "<div>#{node_attrs['title']}</div>"
    when 'hardBreak'
      result << '<br />'
    when 'heading'
      level = node_attrs['level']
      result << "<h#{level}>"
      closing_tag = "</h#{level}>"
    when 'inlineCard'
      url = node_attrs['url']
      result << "[Inline card]: <a href='#{url}'>#{url}</a>"
    when 'listItem'
      result << '<li>'
      closing_tag = '</li>'
    when 'media'
      text = node_attrs['alt'] || node_attrs['id']
      result << "Media: #{text}"
    when 'mediaSingle', 'mediaGroup'
      result << '<div>'
      closing_tag = '</div>'
    when 'mention'
      user = node_attrs['text']
      result << "<b>#{user}</b>"
    when 'orderedList'
      result << '<ol>'
      closing_tag = '</ol>'
    when 'panel'
      type = node_attrs['panelType']
      result << "<div>#{type.upcase}</div>"
    when 'paragraph'
      result << '<p>'
      closing_tag = '</p>'
    when 'rule'
      result << '<hr />'
    when 'status'
      text = node_attrs['text']
      result << text
    when 'table'
      result << '<table>'
      closing_tag = '</table>'
    when 'tableCell'
      result << '<td>'
      closing_tag = '</td>'
    when 'tableHeader'
      result << '<th>'
      closing_tag = '</th>'
    when 'tableRow'
      result << '<tr>'
      closing_tag = '</tr>'
    when 'text'
      marks = adf_marks_to_html node['marks']
      result << marks.collect(&:first).join
      result << node['text']
      result << marks.collect(&:last).join
    when 'taskItem'
      state = node_attrs['state'] == 'TODO' ? '☐' : '☑'
      result << "<li>#{state} "
      closing_tag = '</li>'
    when 'taskList'
      result << "<ul class='taskList'>"
      closing_tag = '</ul>'
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