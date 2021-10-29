# Overview

At a high level, the steps to use this are as follows.

1. Run "bundle install" to install all the appropriate gems for this code. Note that you'll need to be on at least ruby 3.0.0.
2. Create a file with [Jira connection details](#jira-connection-details)
3. Create a file with all the [configuration details](#create-your-project-configuration). What projects, etc.
4. Run "rake download" to pull all the data out of Jira.
5. Run "rake export" to create CSV files from the data that we already got from Jira.

-----

# Jira connection details

Create a file such as "jira.config". The actual name doesn't matter at this point because the main configuration file will contain a reference to it. What goes into this file depends on the type of authentication that you use with your Jira instance.

The code currently only supports two authentication mechanisms with Jira. If you're using Jira cloud then we recommend using the API Token. If you're in Jira Server then you'll have to use the cookie approach.

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

Theoretically you could replace the token with your password for a Jira Server installation but we don't have an environment to test that in. Let us know if you've done this and it works.

## Authentication with cookies ##

This next option is fairly ugly but it does work for Jira Server installations. This is what we usually use for Jira Server.

Once you've logged in with your web browser, your browser will now have authentication cookies saved. If you go into the settings for your brower and copy them, this code can use those cookies for authentication. Generally Jira will set three different cookies and you need them all.

You'll need to refresh the cookies periodically (daily?) so it's annoying but does work.

```json
{
  "cookies": {
    "<key>": "<value>"
  }
}
```

# Create your project configuration

Create the file config.rb file and put a configuration in it like the one below.

```ruby
Exporter.configure do
  # target_path sets the directory that all generated files will end up in.
  target_path 'target'

  # jira_config sets the name of the configuration file with jira specific authentication
  jira_config 'improvingflow.json'

  project do
    # the prefix that will be used for all generated files
    file_prefix 'sample'

    # All the jira specific configuration for this project is in this block. 
    # It will apply to all file sections.
    download do
      project_key 'SP'
      board_id 1
    end

    # All the configuration for one specific output file. There may be multiple file sections.
    file do
      file_suffix '.csv'

      # This is where we massage the data before export. If we want to remove all epics
      # and sub-tasks, do it here. If 
      issues.reject! do |issue|
        %w[Sub-task Epic].include? issue.type
      end

      columns do
        write_headers true

        date 'Done', still_in_status_category('Done')
        date 'Start', first_time_in_status_category('In Progress')
        string 'Type', type
        string 'Key', key
        string 'Summary', summary
      end
    end
end
```

