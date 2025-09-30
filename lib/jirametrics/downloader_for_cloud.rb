# frozen_string_literal: true

class DownloaderForCloud < Downloader
  def jira_instance_type
    'Jira Cloud'
  end

  def search_for_issues jql:, board_id:, path:
    log "  JQL: #{jql}"
    escaped_jql = CGI.escape jql

    hash = {}
    max_results = 5_000 # The maximum allowed by Jira
    next_page_token = nil
    issue_count = 0

    loop do
      relative_url = +''
      relative_url << '/rest/api/3/search/jql'
      relative_url << "?jql=#{escaped_jql}&maxResults=#{max_results}"
      relative_url << "&nextPageToken=#{next_page_token}" if next_page_token
      relative_url << '&fields=updated'

      json = @jira_gateway.call_url relative_url: relative_url
      next_page_token = json['nextPageToken']

      json['issues'].each do |i|
        key = i['key']
        data = DownloadIssueData.new key: key
        data.key = key
        data.last_modified = Time.parse i['fields']['updated']
        data.found_in_primary_query = true
        data.cache_path = File.join(path, "#{key}-#{board_id}.json")
        data.up_to_date = last_modified(filename: data.cache_path) == data.last_modified
        hash[key] = data
        issue_count += 1
      end

      message = "    Found #{issue_count} issues"
      log message, both: true

      break unless next_page_token
    end
    hash
  end

  def bulk_fetch_issues issue_datas:, board:, in_initial_query:
    # We used to use the expand option to pull in the changelog directly. Unfortunately
    # that only returns the "recent" changes, not all of them. So now we get the issue
    # without changes and then make a second call for that changes. Then we insert it
    # into the raw issue as if it had been there all along.
    log "  Downloading #{issue_datas.size} issues", both: true
    payload = {
      # 'expand' => [
      #   'changelog'
      # ],
      'fields' => ['*all'],
      'issueIdsOrKeys' => issue_datas.collect(&:key)
    }
    response = @jira_gateway.post_request(
      relative_url: '/rest/api/3/issue/bulkfetch',
      payload: JSON.generate(payload)
    )

    response['issues'].each do |issue_json|
      issue_json['exporter'] = {
        'in_initial_query' => in_initial_query
      }
      issue = Issue.new(raw: issue_json, board: board)
      data = issue_datas.find { |d| d.key == issue.key }
      data.up_to_date = true
      data.last_modified = issue.updated
      data.issue = issue
    end

    attach_changelog_to_issues issue_datas: issue_datas, issue_jsons: response['issues']

    issue_datas
  end

  def attach_changelog_to_issues issue_datas:, issue_jsons:
    payload = {
      'issueIdsOrKeys' => issue_datas.collect(&:key),
      'maxResults' => 10_000 # The max jira accepts is 10K
    }
    loop do
      puts payload
      response = @jira_gateway.post_request(
        relative_url: '/rest/api/3/changelog/bulkfetch',
        payload: JSON.generate(payload)
      )

      response['issueChangeLogs'].each do |issue_change_log|
        # puts issue_change_log
        # puts issue_change_log.keys.inspect
        issue_id = issue_change_log['issueId']
        issue = issue_datas.find { |data| data.issue.raw['id'] == issue_id }.issue
        # puts "Issue(#{issue.key})"
        histories = issue_change_log['changeHistories']
        issue.raw['changelog'] = {
          'startAt' => 0,
          'maxResults' => histories.size,
          'total' => histories.size,
          'histories' => histories
        }
      end
      next_page_token = response['nextPageToken']
      payload['nextPageToken'] = next_page_token
      # puts "next page token=#{next_page_token.inspect}"
      break if next_page_token.nil?
      # puts ''
    end
  end
end

# {"issueChangeLogs":[
#   {"changeHistories":[
#     {
#       "author":{
#         "accountId":"5b10a2844c20165700ede21g","active":true,"avatarUrls":{"16x16":"https://avatar-management--avatars.server-location.prod.public.atl-paas.net/initials/MK-5.png?size=16&s=16","24x24":"https://avatar-management--avatars.server-location.prod.public.atl-paas.net/initials/MK-5.png?size=24&s=24","32x32":"https://avatar-management--avatars.server-location.prod.public.atl-paas.net/initials/MK-5.png?size=32&s=32","48x48":"https://avatar-management--avatars.server-location.prod.public.atl-paas.net/initials/MK-5.png?size=48&s=48"},"displayName":"Mia Krystof","emailAddress":"mia@example.com","self":"https://your-domain.atlassian.net/rest/api/3/user?accountId=5b10a2844c20165700ede21g","timeZone":"Australia/Sydney"},"created":1492070429,"id":"10001","items":[{"field":"fields","fieldId":"fieldId","fieldtype":"jira","fromString":"old summary","toString":"new summary"}]},{"author":{"accountId":"5b10a2844c20165700ede21g","active":true,"avatarUrls":{"16x16":"https://avatar-management--avatars.server-location.prod.public.atl-paas.net/initials/MK-5.png?size=16&s=16","24x24":"https://avatar-management--avatars.server-location.prod.public.atl-paas.net/initials/MK-5.png?size=24&s=24","32x32":"https://avatar-management--avatars.server-location.prod.public.atl-paas.net/initials/MK-5.png?size=32&s=32","48x48":"https://avatar-management--avatars.server-location.prod.public.atl-paas.net/initials/MK-5.png?size=48&s=48"},"displayName":"Mia Krystof","emailAddress":"mia@example.com","self":"https://your-domain.atlassian.net/rest/api/3/user?accountId=5b10a2844c20165700ede21g","timeZone":"Australia/Sydney"},"created":1492071429,"id":"10002","items":[{"field":"fields","fieldId":"fieldId","fieldtype":"jira","fromString":"old summary 2","toString":"new summary 2"}]}],"issueId":"10100"}],"nextPageToken":"UxAQBFRF"}
