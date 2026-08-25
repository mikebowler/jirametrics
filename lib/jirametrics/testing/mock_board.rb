# frozen_string_literal: true

# Builds a Board from the two files jirametrics already downloads for you, so a test can use your
# own board rather than a fabricated one.
#
#   board = MockBoard.load statuses: 'target/mine_statuses.json',
#                          configuration: 'target/mine_board_1_configuration.json'
#
# Takes filenames rather than packaging a sample board, because a board that resembles yours is
# worth more than one of ours, and because sample data would have to be carried in the gem forever.
class MockBoard
  class << self
    def load statuses:, configuration:
      board = Board.new(
        raw: JSON.parse(File.read(configuration, encoding: 'UTF-8')),
        possible_statuses: load_statuses(statuses)
      )
      board.project_config = ProjectConfig.new(
        exporter: Exporter.new, target_path: File.dirname(configuration), jira_config: nil, block: nil
      )
      board
    end

    def load_statuses filename
      JSON.parse(File.read(filename, encoding: 'UTF-8')).each_with_object(StatusCollection.new) do |raw, collection|
        collection << Status.from_raw(raw)
      end
    end
  end
end
