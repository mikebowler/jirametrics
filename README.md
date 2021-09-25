# Step 1: Create a jira_config.json document

You can copy the default_jira.config and put your own values in it.

# Step 2: Create your configuration in config.rb

Create a config.rb file and put a configuration in it like the one below.

```ruby
class Config < ConfigBase
    target_path 'target/'
    jira_config 'improvingflow'

    project file_prefix: 'sample', project: 'SP' do
        issues.reject! do |issue|
            ['Sub-task', 'Epic'].include? issue.type
        end

        columns write_headers: true do
            date 'Done', still_in_status_category('Done')
            date 'Start', first_time_in_status_category('In Progress')
            string 'Type', type
            string 'Key', key
            string 'Summary', summary
        end
    end
end
```

# Step 3: Install the gems you'll need

Run "bundle install" to install all the gems you'll need. You'll need to be on at least Ruby 3.0.0.

# Step 4: Run it

From the command line, "rake download" will pull the data from Jira and store it in the target path specified. If you didn't specify a path then it defauls to "target/".

"rake extract" will take those files you already downloaded and will generate CSV files from it. Those CSV's will also be in the target directory.

"rake" with no parameters will do a download followed by an extract.

----

# Configuring authentication with Jira #

# Configuring the project #