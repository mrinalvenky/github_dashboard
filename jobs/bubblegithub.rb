#!/usr/bin/env ruby
require 'net/http'
require 'json'

# This job will plot the metrics of all collaborators of a repo
# as a bubble graph

# Config
# ------
github_reponame = ENV['GITHUB_REPONAME'] || 'shopify/dashing'
points_x = [] 
points_y = [] 
points_z = [] 
points_group = [] 
max_users = 11

SCHEDULER.every '3m', :first_in => 0 do |job|
  http = Net::HTTP.new("api.github.com", Net::HTTP.https_default_port())
  http.use_ssl = true
  
  total_users = 0
  oldest_week = 9999999999
  total_commitsize = 0
  total_commit = 0
  total_age = 0
  max_commitsize = 0
  max_commit = 0
  max_age = 0

  # Get the list of contributors from the repo
  response = http.request(Net::HTTP::Get.new("/repos/#{github_reponame}/stats/contributors"))
  data = JSON.parse(response.body)
  
  if response.code == "200"
      data.each do |datum|

          # get the values for each contributor
          if datum['author']
              name = datum['author']['login']
          else
              name = "Anonymous"
          end

          commits = datum['total']
          total_commit += datum['total']

          first_commit = false
          commitsize = 0
          age = 1

          datum['weeks'].each do |wk|
              if wk['w'] < oldest_week
                  oldest_week = wk['w']
              end
              if first_commit == false && (wk['a'] != 0 || wk['d'] != 0)
                  age = wk['w'] - oldest_week + 1
                  total_age += age
                  first_commit = true
              end
              commitsize += wk['a'] + wk['d']
              total_commitsize += wk['a'] + wk['d']
          end


          # Insert into the points table
          points_x.insert(total_users, commits)
          if max_commit < commits
             max_commit = commits
          end
          points_y.insert(total_users, commitsize)
          if max_commitsize < commitsize
             max_commitsize = commitsize
          end
          points_z.insert(total_users, age)
          if max_age < age
             max_age = age
          end
          points_group.insert(total_users, name)
          
          total_users += 1
          
      end
  else
      puts "github api error (status-code: #{response.code})\n#{response.body}"
      break
  end

  normal_points = []

  #Github shows bigger values at the end so reverse
  points_x.reverse!
  points_y.reverse!
  points_z.reverse!
  points_group.reverse!
  
  # Calculate normalized values
  (0..(total_users - 1)).each do |i|
      nx = (points_x[i] * 100) / max_commit
      ny = (points_y[i] * 100) / max_commitsize
      nz = (points_z[i] * 5) / max_age
      normal_points << { x: nx, y: ny, z: nz, group: points_group[i]}
      if i > max_users
          break
      end
  end

  send_event('bubblegithub', points: normal_points)

end
