# frozen_string_literal: true

require './spec/spec_helper'

describe AtlassianDocumentFormat do
  let(:format) { described_class.new users: [], timezone_offset: '+00:00' }

  context 'expand_account_id' do
    it 'handles no matches' do
      expect(format.expand_account_id 'no-match').to eq "<span class='account_id'>no-match</span>"
    end

    it 'finds a match in users' do
      format.users << mock_user(
        display_name: 'Fred Flintstone',
        account_id: '557058:aaccdddd-0be8-432f-959a-13d34c55315f',
        avatar_url: 'https://example.com/fred.png'
      )
      expect(format.expand_account_id '557058:aaccdddd-0be8-432f-959a-13d34c55315f').to eq(
        "<span class='account_id'>@Fred Flintstone</span>"
      )
    end
  end

  context 'v2 to_html' do
    it 'ignores plain text' do
      expect(format.to_html 'foobar').to eq 'foobar'
    end

    it 'converts color declarations' do
      input = 'one {color:#bf2600}bold Red{color} two ' \
        '{color:#403294}Bold purple{color} ' \
        'three {color:#b3f5ff}Subtle teal{color}'
      expect(format.to_html input).to eq(
        'one <span style="color: #bf2600">bold Red</span> ' \
        'two <span style="color: #403294">Bold purple</span> ' \
        'three <span style="color: #b3f5ff">Subtle teal</span>'
      )
    end

    it 'converts urls' do
      input = 'a [link|http://example.com] embedded'
      expect(format.to_html input).to eq(
        'a <a href="http://example.com">link</a> embedded'
      )
    end

    it 'converts comment with only a list' do
      input = "* one\n* two"
      expect(format.to_html input).to eq(
        '* one<br />* two'
      )
    end

    it 'converts account id' do
      input = 'foo [~accountid:abcdef] bar'
      expect(format.to_html input).to eq(
        "foo <span class='account_id'>abcdef</span> bar"
      )
    end
  end

  context 'v3 to_html' do
    it 'handles single paragraph' do
      input = {
        'type' => 'doc',
        'version' => 1,
        'content' => [
          {
            'type' => 'paragraph',
            'content' => [
              {
                'type' => 'text',
                'text' => 'Comment 2'
              }
            ]
          }
        ]
      }
      expect(format.to_html input).to eq '<p>Comment 2</p>'
    end

    it 'single paragraph with a bold word' do
      input = {
        'version' => 1,
        'type' => 'doc',
        'content' => [
          {
            'type' => 'paragraph',
            'content' => [
              {
                'type' => 'text',
                'text' => 'Hello '
              },
              {
                'type' => 'text',
                'text' => 'world',
                'marks' => [
                  {
                    'type' => 'strong'
                  }
                ]
              }
            ]
          }
        ]
      }
      expect(format.to_html input).to eq '<p>Hello <b>world</b></p>'
    end

    it 'handles two simple paragraphs with only text' do
      input = {
        'type' => 'doc',
        'version' => 1,
        'content' => [
          {
            'type' => 'paragraph',
            'content' => [
              {
                'type' => 'text',
                'text' => 'paragraph 1'
              }
            ]
          },
          {
            'type' => 'paragraph',
            'content' => [
              {
                'type' => 'text',
                'text' => 'paragraph 2'
              }
            ]
          }
        ]
      }
      expect(format.to_html input).to eq "<p>paragraph 1</p>\n<p>paragraph 2</p>"
    end
  end

  context 'adf_node_to_html' do
    it 'is simple list' do
      input = {
        'type' => 'bulletList',
        'content' => [
          {
            'type' => 'listItem',
            'content' => [
              {
                'type' => 'paragraph',
                'content' => [
                  {
                    'type' => 'text',
                    'text' => 'one'
                  }
                ]
              }
            ]
          },
          {
            'type' => 'listItem',
            'content' => [
              {
                'type' => 'paragraph',
                'content' => [
                  {
                    'type' => 'text',
                    'text' => 'two'
                  }
                ]
              }
            ]
          }
        ]
      }
      expect(format.adf_node_to_html input).to eq '<ul><li><p>one</p></li><li><p>two</p></li></ul>'
    end

    it 'is an ordered list' do
      input = {
        'type' => 'orderedList',
        'content' => [
          {
            'type' => 'listItem',
            'content' => [
              {
                'type' => 'paragraph',
                'content' => [
                  {
                    'type' => 'text',
                    'text' => 'one'
                  }
                ]
              }
            ]
          }
        ]
      }
      expect(format.adf_node_to_html input).to eq '<ol><li><p>one</p></li></ol>'
    end

    it 'has colour' do
      input = {
        'type' => 'text',
        'text' => 'Hello world',
        'marks' => [
          {
            'type' => 'textColor',
            'attrs' => {
              'color' => '#97a0af'
            }
          }
        ]
      }
      expect(format.adf_node_to_html input).to eq "<span style='color: #97a0af'>Hello world</span>"
    end

    it 'has a link' do
      input = {
        'type' => 'text',
        'text' => 'Hello world',
        'marks' => [
          {
            'type' => 'link',
            'attrs' => {
              'href' => 'http://example.com',
              'title' => 'Example'
            }
          }
        ]
      }

      expect(format.adf_node_to_html input).to eq "<a href='http://example.com' title='Example'>Hello world</a>"
    end

    it 'has a mention' do
      input = {
        'type' => 'mention',
        'attrs' => {
          'id' => 'ABCDE-ABCDE-ABCDE-ABCDE',
          'text' => '@Fred Flintstone',
          'userType' => 'APP'
        }
      }

      expect(format.adf_node_to_html input).to eq '<b>@Fred Flintstone</b>'
    end

    it 'has a table' do
      input = {
        'type' => 'table',
        'attrs' => {
          'isNumberColumnEnabled' => false,
          'layout' => 'center',
          'width' => 900,
          'displayMode' => 'default'
        },
        'content' => [
          {
            'type' => 'tableRow',
            'content' => [
              {
                'type' => 'tableCell',
                'attrs' => {},
                'content' => [
                  {
                    'type' => 'paragraph',
                    'content' => [
                      {
                        'type' => 'text',
                        'text' => ' Row one, cell one'
                      }
                    ]
                  }
                ]
              },
              {
                'type' => 'tableCell',
                'attrs' => {},
                'content' => [
                  {
                    'type' => 'paragraph',
                    'content' => [
                      {
                        'type' => 'text',
                        'text' => 'Row one, cell two'
                      }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      }
      expect(format.adf_node_to_html input).to eq(
        '<table><tr><td><p> Row one, cell one</p></td><td><p>Row one, cell two</p></td></tr></table>'
      )
    end
  end

  it 'has task list' do
    input = {
      'type' => 'taskList',
      'content' => [
        {
          'type' => 'taskItem',
          'content' => [
            {
              'type' => 'text',
              'text' => 'One thing '
            }
          ],
          'attrs' => {
            'localId' => '1e547f4f-ff44-494b-b22d-06cb78eaf5f1',
            'state' => 'DONE'
          }
        },
        {
          'type' => 'taskItem',
          'content' => [
            {
              'type' => 'text',
              'text' => 'Another thing'
            }
          ],
          'attrs' => {
            'localId' => '0f0664a5-76c2-4a8c-b834-f3445aa9076f',
            'state' => 'TODO'
          }
        }
      ],
      'attrs' => {
        'localId' => '5ed5b805-e2b9-49b5-adf2-2b8b54e4b63e'
      }
    }
    expect(format.adf_node_to_html input).to eq(
      "<ul class='taskList'><li>☑ One thing </li><li>☐ Another thing</li></ul>"
    )
  end

  it 'has emoji' do
    input = {
      'type' => 'emoji',
      'attrs' => {
        'shortName' => ':grinning:',
        'text' => '😀'
      }
    }
    expect(format.adf_node_to_html input).to eq(
      '😀'
    )
  end

  it 'has hard break' do
    input = {
      'type' => 'hardBreak'
    }
    expect(format.adf_node_to_html input).to eq('<br />')
  end

  it 'has heading' do
    input = {
      'type' => 'heading',
      'attrs' => {
        'level' => 2
      },
      'content' => [
        {
          'type' => 'text',
          'text' => 'Foo'
        }
      ]
    }

    expect(format.adf_node_to_html input).to eq('<h2>Foo</h2>')
  end

  it 'has code block' do
    input = {
      'type' => 'codeBlock',
      'attrs' => {
        'language' => 'javascript'
      },
      'content' => [
        {
          'type' => 'text',
          'text' => 'var foo = 1;'
        }
      ]
    }

    expect(format.adf_node_to_html input).to eq('<code>var foo = 1;</code>')
  end

  it 'has inline card' do
    input = {
      'type' => 'inlineCard',
      'attrs' => {
        'url' => 'https://atlassian.com'
      }
    }
    expect(format.adf_node_to_html input).to eq(
      "[Inline card]: <a href='https://atlassian.com'>https://atlassian.com</a>"
    )
  end

  it 'has media single' do
    input = {
      'type' => 'mediaSingle',
      'attrs' => {
        'layout' => 'center'
      },
      'content' => [
        {
          'type' => 'media',
          'attrs' => {
            'id' => '4478e39c-cf9b-41d1-ba92-68589487cd75',
            'type' => 'file',
            'collection' => 'MediaServicesSample',
            'alt' => 'moon.jpeg',
            'width' => 225,
            'height' => 225
          }
        }
      ]
    }
    expect(format.adf_node_to_html input).to eq(
      '<div>Media: moon.jpeg</div>'
    )
  end

  it 'has media group' do
    input = {
      'type' => 'mediaGroup',
      'content' => [
        {
          'type' => 'media',
          'attrs' => {
            'type' => 'file',
            'id' => '6e7c7f2c-dd7a-499c-bceb-6f32bfbf30b5',
            'collection' => 'ae730abd-a389-46a7-90eb-c03e75a45bf6'
          }
        }
      ]
    }
    expect(format.adf_node_to_html input).to eq(
      '<div>Media: 6e7c7f2c-dd7a-499c-bceb-6f32bfbf30b5</div>'
    )
  end

  it 'has blockquote' do
    input = {
      'type' => 'blockquote',
      'content' => [
        {
          'type' => 'paragraph',
          'content' => [
            {
              'type' => 'text',
              'text' => 'Hello world'
            }
          ]
        }
      ]
    }

    expect(format.adf_node_to_html input).to eq(
      '<blockquote><p>Hello world</p></blockquote>'
    )
  end

  it 'has date' do
    input = {
      'type' => 'date',
      'attrs' => {
        'timestamp' => '1753142400000'
      }
    }

    expect(format.adf_node_to_html input).to eq(
      '2025-07-21'
    )
  end

  it 'has a divider (rule)' do
    input = {
      'type' => 'rule'
    }

    expect(format.adf_node_to_html input).to eq(
      '<hr />'
    )
  end

  it 'has a status' do
    input = {
      'type' => 'status',
      'attrs' => {
        'localId' => 'abcdef12-abcd-abcd-abcd-abcdef123456',
        'text' => 'In Progress',
        'color' => 'yellow'
      }
    }
    expect(format.adf_node_to_html input).to eq(
      'In Progress'
    )
  end

  it 'has a panel' do
    input = {
      'type' => 'panel',
      'attrs' => {
        'panelType' => 'info'
      },
      'content' => [
        {
          'type' => 'paragraph',
          'content' => [
            {
              'type' => 'text',
              'text' => 'Hello world'
            }
          ]
        }
      ]
    }
    expect(format.adf_node_to_html input).to eq(
      '<div>INFO</div><p>Hello world</p>'
    )
  end

  it 'has an expand' do
    input = {
      'type' => 'expand',
      'attrs' => {
        'title' => 'Click me'
      },
      'content' => [
        {
          'type' => 'paragraph',
          'content' => [
            {
              'type' => 'text',
              'text' => 'Hello world'
            }
          ]
        }
      ]
    }

    expect(format.adf_node_to_html input).to eq(
      '<div>Click me</div><p>Hello world</p>'
    )
  end

  it 'has an expand' do
    input = {
      'type' => 'decisionList',
      'content' => [
        {
          'type' => 'decisionItem',
          'content' => [
            {
              'type' => 'text',
              'text' => 'A decision'
            }
          ],
          'attrs' => {
            'localId' => 'bc436863-84c9-4332-85a8-21478ed203a1',
            'state' => 'DECIDED'
          }
        }
      ],
      'attrs' => {
        'localId' => 'd00434e6-e76e-4098-a8df-4833c8ddba40'
      }
    }

    expect(format.adf_node_to_html input).to eq(
      '<div>Decisions<ul><li>A decision</li></ul></div>'
    )
  end
end
