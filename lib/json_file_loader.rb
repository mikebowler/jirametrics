require 'json'

class JsonFileLoader
  def load filename
    JSON.parse File.read(filename)
  end
end
