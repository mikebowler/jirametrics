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
        .gsub(/\[([^|]+)\|(https?[^\]]+)\]/, '<a href="\2">\1</a>') # URLs
        .gsub("\n", '<br />')
    elsif input&.[]('content')
      input['content'].collect { |element| adf_node_to_html element }.join("\n")
    else
      # We have an actual ADF document with no content.
      ''
    end
  end

  def to_text input
    if input.is_a? String
      input
    elsif input&.[]('content')
      input['content'].collect { |element| adf_node_to_text element }.join
    else
      ''
    end
  end

  # ADF is Atlassian Document Format
  # https://developer.atlassian.com/cloud/jira/platform/apis/document/structure/
  def adf_node_to_html node # rubocop:disable Metrics/CyclomaticComplexity
    adf_node_render(node) do |n|
      node_attrs = n['attrs']
      case n['type']
      when 'blockquote'                then ['<blockquote>', '</blockquote>']
      when 'bulletList'                then ['<ul>', '</ul>']
      when 'codeBlock'                 then ['<code>', '</code>']
      when 'date'
        [Time.at(node_attrs['timestamp'].to_i / 1000, in: @timezone_offset).to_date.to_s, nil]
      when 'decisionItem'              then ['<li>', '</li>']
      when 'decisionList'              then ['<div>Decisions<ul>', '</ul></div>']
      when 'emoji'                     then [node_attrs['text'], nil]
      when 'expand'                    then ["<div>#{node_attrs['title']}</div>", nil]
      when 'hardBreak'                 then ['<br />', nil]
      when 'heading'
        level = node_attrs['level']
        ["<h#{level}>", "</h#{level}>"]
      when 'inlineCard'
        url = node_attrs['url']
        ["[Inline card]: <a href='#{url}'>#{url}</a>", nil]
      when 'listItem'                  then ['<li>', '</li>']
      when 'media'
        text = node_attrs['alt'] || node_attrs['id']
        ["Media: #{text}", nil]
      when 'mediaSingle', 'mediaGroup' then ['<div>', '</div>']
      when 'mention'                   then ["<b>#{node_attrs['text']}</b>", nil]
      when 'orderedList'               then ['<ol>', '</ol>']
      when 'panel'                     then ["<div>#{node_attrs['panelType'].upcase}</div>", nil]
      when 'paragraph'                 then ['<p>', '</p>']
      when 'rule'                      then ['<hr />', nil]
      when 'status'                    then [node_attrs['text'], nil]
      when 'table'                     then ['<table>', '</table>']
      when 'tableCell'                 then ['<td>', '</td>']
      when 'tableHeader'               then ['<th>', '</th>']
      when 'tableRow'                  then ['<tr>', '</tr>']
      when 'text'
        marks = adf_marks_to_html(n['marks'])
        [marks.collect(&:first).join + n['text'], marks.collect(&:last).join]
      when 'taskItem'
        state = node_attrs['state'] == 'TODO' ? '☐' : '☑'
        ["<li>#{state} ", '</li>']
      when 'taskList'                  then ["<ul class='taskList'>", '</ul>']
      else
        ["<p>Unparseable section: #{n['type']}</p>", nil]
      end
    end
  end

  def adf_node_to_text node # rubocop:disable Metrics/CyclomaticComplexity
    adf_node_render(node) do |n|
      node_attrs = n['attrs']
      case n['type']
      when 'blockquote'                then ['', nil]
      when 'bulletList'                then ['', nil]
      when 'codeBlock'                 then ['', nil]
      when 'date'
        [Time.at(node_attrs['timestamp'].to_i / 1000, in: @timezone_offset).to_date.to_s, nil]
      when 'decisionItem'              then ['- ', "\n"]
      when 'decisionList'              then ["Decisions:\n", nil]
      when 'emoji'                     then [node_attrs['text'], nil]
      when 'expand'                    then ["#{node_attrs['title']}\n", nil]
      when 'hardBreak'                 then ["\n", nil]
      when 'heading'                   then ['', "\n"]
      when 'inlineCard'                then [node_attrs['url'], nil]
      when 'listItem'                  then ['- ', nil]
      when 'media'
        text = node_attrs['alt'] || node_attrs['id']
        ["Media: #{text}", nil]
      when 'mediaSingle', 'mediaGroup' then ['', nil]
      when 'mention'                   then [node_attrs['text'], nil]
      when 'orderedList'               then ['', nil]
      when 'panel'                     then ["#{node_attrs['panelType'].upcase}\n", nil]
      when 'paragraph'                 then ['', "\n"]
      when 'rule'                      then ["---\n", nil]
      when 'status'                    then [node_attrs['text'], nil]
      when 'table'                     then ['', nil]
      when 'tableCell'                 then ['', "\t"]
      when 'tableHeader'               then ['', "\t"]
      when 'tableRow'                  then ['', "\n"]
      when 'text'                      then [n['text'], nil]
      when 'taskItem'
        state = node_attrs['state'] == 'TODO' ? '☐' : '☑'
        ["#{state} ", "\n"]
      when 'taskList'                  then ['', nil]
      else
        ["[Unparseable: #{n['type']}]\n", nil]
      end
    end
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

  private

  def adf_node_render node, &render_node
    prefix, suffix = render_node.call(node)
    result = +(prefix || '')
    node['content']&.each { |child| result << adf_node_render(child, &render_node) }
    result << suffix if suffix
    result
  end
end
