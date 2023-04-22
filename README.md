# Overview

This project is designed to pull data out of Jira (either Cloud or Server) and make them available in a useful format. 

You can export CSV files that can be used with various spreadsheets, like the excellent ones from [Focused Objective](https://www.focusedobjective.com/w/support/) or with tools like [Actionable Agile](https://analytics.actionableagile.com).

Alternatively, this tool can directly [generate HTML](https://github.com/mikebowler/jira-export/wiki/HTML-Reports) files with pretty charts in them.

* Installation
* Configuring [how it connects to Jira](https://github.com/mikebowler/jira-export/wiki/Jira-Configuration).
* Configuring the [common portions of the export](https://github.com/mikebowler/jira-export/wiki/Common-configuration)
* Specifically configuring it to [export raw data](https://github.com/mikebowler/jira-export/wiki/Exporting-raw-data) or to generate [HTML reports](https://github.com/mikebowler/jira-export/wiki/HTML-Reports). (You'll need to set one of these)
* Running it (see below)
* [Change log](https://github.com/mikebowler/jira-export/wiki/Changes)

# Overview

At a high level, the steps to use this are as follows.

1. Run "bundle install" to install all the appropriate gems for this code. Note that you'll need to be on at least [ruby](https://www.ruby-lang.org/en/) 3 or higher. This will work with [JRuby](https://www.jruby.org) 9.4 or higher, if you prefer to run it on a Java Virtual Machine.
2. Create a file with [Jira connection details](#jira-connection-details)
3. Create a file with all the [configuration details](#create-your-project-configuration). What projects, etc.
4. Run "rake download" to pull all the data out of Jira.
5. Run "rake export" to create CSV files (or HTML reports) from the data that we already got from Jira.
