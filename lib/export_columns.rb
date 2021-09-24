class ExportColumns < BasicObject
    attr_reader :columns

    def initialize config
        @columns = []
        @config = config
    end

    def date label, proc
        @columns << [:date, label, proc]
    end

    def string label, proc
        @columns << [:string, label, proc]
    end

    # Why is this here? Because I keep forgetting that puts() will be caught by method_missing and
    # that makes me spin through a debug cycle. So I make it do the expected thing.
    def puts *args
        $stdout.puts *args
    end

    def method_missing method_name, *args, &block
        # Have to reference config outside the lambda so that it's accessible inside.
        # When the lambda is executed for real, it will be running inside the context of an Issue
        # object and at that point @config won't be referencing a variable from the right object.
        config = @config

        -> (issue) do
            parameters = issue.method(method_name.to_sym).parameters
            # Is the first parameter called config?
            if parameters.empty? == false && parameters[0][1] == :config
                new_args = [config] + args
                issue.__send__ method_name, *new_args
            else
                issue.__send__ method_name, *args 
            end
        end # *([config] + args) }
    end
end