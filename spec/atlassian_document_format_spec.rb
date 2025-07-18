# frozen_string_literal: true

require './spec/spec_helper'

describe AtlassianDocumentFormat do
  let(:format) { described_class.new users: [] }

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
end
