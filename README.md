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
  "url": "https://<your_url>",
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

## Top level config ##

In the top level of the config file, you can have multiple projects and can set the locations of the target path and jira configuration file.

Putting an x in front of project will cause that project to be ignored.

```ruby
Exporter.configure do
  target_path 'target'
  jira_config 'improvingflow.json'

  project do
    # ... project 1 ...
  end

  project do
    # ... project 2 ...
  end

  xproject do
    # ... ignored project ...
  end
end
```

What if you need to have different target paths or jira config for different projects? Each project will find the preceeding settings and use those so you can redefine them at any time and the subsequent projects will use the new settings.

```ruby
Exporter.configure do
  target_path 'target'
  jira_config 'improvingflow.json'

  project do
    # ... project 1 ...
  end

  target_path 'target2'
  jira_config 'other.json'

  project do
    # ... project 2 using different target and jira config ...
  end
end
```

## Project configuration ##

The **file_prefix** will be used in the filenames of all files created during download or during the export.

The **download** section contains all the information specific to the project in Jira. There can only be one of these.

The **file** section contains information specific to the output file we're going to create. There can be multiples of these, if we're generating multiple different files.

```ruby
project do
  file_prefix 'sample'

  download do
    # ...
  end

  file do
    # ...
  end
end
```

## Download configuration ##

If you specify one or more of **project_key**, **filter**, or **rolling_date_count** then the program will generate a JQL statement for you and will use that. If you pass in a JQL statement then it will ignore all of the previous values and use only that.

It's unlikely that you would want to specify both a **project_key** and a **filter** although you can, if you really want.

The **rolling_date_count** indicates how many days back we're looking for files. For example, if we say "rolling_date_count 90" then we're retrieving any items that have closed in the last 90 days. We always return items that are still open, regardless of date. If this field isn't specified then we retrieve all issues that have ever been in this project and that's usually undesirable.

If you specify a **board_id** then we do an extra request to Jira to query information about that board. This is neccessary if you want to work with status categories, for example.

```ruby
download do
  project_key 'SP'
  filter 'filtername'
  rolling_date_count 90
  board_id 1
end
```

## File configuration ##

This section contains information about a specific file that we want to export.

**file_suffix** specifies the suffix that will be used for the generated file. If not specified, it defaults to '.csv'

The **columns** block provides information about the actual data that will be exported.

**only_use_row_if** is a bit of a hack to exclude rows that we don't want to see in the export. For example, sometimes we only want to write a row if it has either a start date or an end date or both. We could use this to exclude the row unless one of those values is present.

The full list of issues is made available in the **issues** variable so it's possible to do things like exclude issues we don't want. The sample below is excluding any issues that are either epics or sub-tasks. We'll often use it to exclude specific issues that we know have bad data.

```ruby
file do
  file_suffix '.csv'

  issues.reject! do |issue|
    %w[Sub-task Epic].include? issue.type
  end

  only_use_row_if do |row|
    row[0] || row[1]
  end
end
```

## Columns config ##

**write_headers** indicates whether we want a header row in the output or not. The default is false.

The **date** and **string** lines will output one of those data types into a column in the output file. The first parameter that they're passed is the name of the column and the second is a method that will be called on the Issue class. Each of those latter options are described below.

```ruby
columns do
  write_headers true

  date 'Done', still_in_status_category('Done')
  date 'Start', first_time_in_status_category('In Progress')
  string 'Type', type
  string 'Key', key
  string 'Summary', summary
end
```

**column_entry_times** will autogenerate multiple columns based on the columns found on your board and will put an entry date in each of those columns. This is useful for tools like Actionable Agile that need entry times per column. Note that to use this option, you must have specified a board_id in the project.

```ruby
columns do
  write_headers true

  string 'ID', key
  string 'link', url
  string 'title', summary
  column_entry_times
end
```

### Methods to retrieve data ###

* **first_time_in_status** takes a list of status names and returns the timestamp of the first time the issue entered any of these statuses.
* **first_time_not_in_status** takes a list of status names and returns the timestamp of the first time that the issue is NOT in one of these statuses. Commonly used if there are a couple of columns at the beginning of the board that we don't want to consider for the purposes of calculating cycletime.
* **still_in_status** Takes a list of status names. If an issue has ever been in one of these statuses AND is still in one of these statuses then was was the last time it entered one? This is useful for tracking cases where an item moves forward on the board, then backwards, then forward again. We're tracking the last time it entered the named status.
* **first_time_in_status_category** Same as first_time_in_status except that it's checking status categories.
* **still_in_status_category** Same as still_in_status except that it's checking status categories.
* **first_status_change_after_created** Returns the timestamp of the first status change after the issue was created.
* **time_created** Returns the creation timestamp of the issue
* **key** The Jira issue number
* **type** The issue type
* **summary** The issue description
* **url** The issue URL. Note that this is not actually found in the data that Jira provides us so we fabricate it from information we do have. It's possible that the URL we generate won't work although it has in all the cases we've tested.
* **blocked_percentage** Takes two of the above date methods (first for the start time and second for the end time) and then calculates the percentage of time that this issue was marked as blocked (flagged in Jira parlance).


What if there aren't any built-in methods to extract the piece of data that you want? You can pass in an arbitrary bit of code that will get executed for each issue.

```ruby
columns do
  string 'sprint_count', ->(issue) { issue.get_whatever_data_you_want }
end
```

