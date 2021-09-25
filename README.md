# Step 1: Create a jira_config.json document

You can copy the default_jira.config and put your own values in it. The code currently only supports two authentication mechanisms with Jira. If you're using Jira cloud then we recommend using the API Token. If you're in Jira Server then you'll have to use the cookie approach.

## Authentication with the API Token ##

Navigate to https://id.atlassian.com/manage-profile/security/api-tokens and create an API token. Insert that token in the jira.config like this:

```json
{
  "url": "https://improvingflow.atlassian.net",
  "email": "<your email>",
  "api_token": "<your_api_key>",
}
```

Note that API Tokens only work with Jira cloud at this time. If you're using Jira Server, you're out of luck.

Theoretically you could replace the token with your password but we haven't tested that.

## Authentication with cookies ##

Once you've logged in with your web browser, your browser will now have authentication cookies saved. If you go into the settings for your brower and copy them, this code can use those cookies for authentication. Yes, this is extremely ugly but it's been the only way we could get authentication working in some cases. Generally Jira will set three different cookies and you need them all.

```json
{
  "cookies": {
    "<key>": "<value>"
  }
}
```

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



# Configuring the project #