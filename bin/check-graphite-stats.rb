#! /usr/bin/env ruby
#
#   check-stats
#
# DESCRIPTION:
#   Checks metrics in Graphite, averaged over a period of time.
#
#   The fired Sensu event will only be critical if a stat is
#   above the critical threshold. Otherwise, the event will be warning,
#   if a stat is above the warning threshold.
#
#   Multiple stats will be checked if * are used
#   in the "target" query.
#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#
# USAGE:
#   example commands
#
# NOTES:
#
# LICENSE:
#   Alan Smith (alan@asmith.me)
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'json'
require 'net/http'
require 'sensu-plugin/check/cli'

class CheckGraphiteStat < Sensu::Plugin::Check::CLI
  option :host,
         short: '-h HOST',
         long: '--host HOST',
         description: 'Graphite hostname',
         proc: proc(&:to_s),
         default: 'graphite'

  option :period,
         short: '-p PERIOD',
         long: '--period PERIOD',
         description: 'The period back in time to extract from Graphite. Use -24hours, -2days, -15mins, etc, same format as in Graphite',
         proc: proc(&:to_s),
         required: true

  option :target,
         short: '-t TARGET',
         long: '--target TARGET',
         description: 'The Graphite metric name. Can include * to query multiple metrics',
         proc: proc(&:to_s),
         required: true

  option :warn,
         short: '-w WARN',
         long: '--warn WARN',
         description: 'Warning level',
         proc: proc(&:to_f),
         required: false

  option :crit,
         short: '-c CRIT',
         long: '--crit CRIT',
         description: 'Critical level',
         proc: proc(&:to_f),
         required: false

  option :unknown_ignore,
         short: '-u',
         long: '--unknown-ignore',
         description: "Do nothing for UNKNOWN status (when you wildcard-match a ton of metrics at once and you don't care about a few missing data)",
         boolean: true,
         default: false

  option :reverse_scale,
         short: '-r',
         long: '--reverse-scale',
         description: 'Reverse the warn/crit scale (if value is less than instead of greater than)',
         boolean: true,
         default: false

  def average(a)
    total = 0
    a.to_a.each { |i| total += i.to_f }

    total / a.length
  end

  def danger(metric)
    datapoints = metric['datapoints'].map(&:first).compact

    # #YELLOW
    unless datapoints.empty? # rubocop:disable UnlessElse
      avg = average(datapoints)
      if config[:reverse_scale] == false
        if !config[:crit].nil? && avg > config[:crit]
          return [2, "#{metric['target']} is #{avg}"]
        elsif !config[:warn].nil? && avg > config[:warn]
          return [1, "#{metric['target']} is #{avg}"]
        end
      else
        if !config[:crit].nil? && avg < config[:crit] # rubocop:disable Style/IfInsideElse
          return [2, "#{metric['target']} is #{avg}"]
        elsif !config[:warn].nil? && avg < config[:warn]
          return [1, "#{metric['target']} is #{avg}"]
        end
      end
    else
      return [3, "#{metric['target']} has no datapoints"] unless config[:unknown_ignore]
    end
    [0, nil]
  end

  def run
    body =
      begin
        uri = URI.parse(URI.encode("http://#{config[:host]}/render?format=json&target=#{config[:target]}&from=#{config[:period]}"))
        res = Net::HTTP.get_response(uri)
        res.body
      rescue => e
        warning "Failed to query Graphite: #{e.inspect}"
      end

    status = 0
    message = ''
    data =
      begin
        JSON.parse(body)
      rescue
        []
      end

    unknown 'No data from Graphite' if data.empty?

    data.each do |metric|
      s, msg = danger(metric)

      message += "#{msg} " unless s.zero?
      status = s unless s < status
    end

    if status == 2
      critical message
    elsif status == 1
      warning message
    elsif status == 3
      unknown message
    end
    ok
  end
end
