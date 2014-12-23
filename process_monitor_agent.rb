#!/usr/bin/env ruby
require 'rubygems'
require 'bundler/setup'
require 'newrelic_plugin'
require 'sys/proctable'
include Sys

module NewRelic::ProcessMonitorAgent

  class Agent < NewRelic::Plugin::Agent::Base
    agent_guid 'com.indigobiosystems.process_monitor'
    agent_config_options :endpoint, :processes, :agent_name, :debug
    agent_human_labels('ProcessMonitor') { "#{agent_name}" }
    agent_version '1.0.0'

    def setup_metrics
      self.debug = debug
      self.agent_name ||= endpoint
    end

    def poll_cycle
      begin
        if "#{self.debug}" == "true"
          puts '[Process Monitor] Debug mode on: metric data will not be sent to New Relic'
        end

        # Examples
        #counter_track(stats, %w(asserts user), 'user')
        #track(stats, %w(connections current), 'current')

        processes.each do |search|
          rss = 0
          percent_memory = 0
          percent_cpu = 0
          child_count = 0

          process_list = ProcTable.ps.select { |p| p.cmdline.include?(search) }
          process_count = process_list.count
          process_list.each do |process|
            rss = rss + rss_of(process)
            percent_memory = percent_memory + percent_memory_of(process)
            percent_cpu = percent_cpu + percent_cpu_of(process)
            children = children_of(process)
            children.each do |child|
              rss = rss + rss_of(child)
              percent_memory = percent_memory + percent_memory_of(child)
              percent_cpu = percent_cpu + percent_cpu_of(child)
            end
            child_count = child_count + children.count
          end

          process_count = process_count + child_count

          report_metric_check_debug("Process/#{search}/process count", 'count', process_count)
          report_metric_check_debug("Process/#{search}/rss", 'bytes', rss)
          report_metric_check_debug("Process/#{search}/percent cpu", 'percentage', percent_cpu)
          report_metric_check_debug("Process/#{search}/percent memory", 'percentage', percent_memory)
        end

      rescue => e
        $stderr.puts "#{e}: #{e.backtrace.join("\n   ")}"
      end
    end

    def percent_cpu_of(process)
      process['pctcpu'] or 0
    end

    def percent_memory_of(process)
      process['pctmem'] or 0
    end

    def rss_of(process)
      process['rss'] or 0
    end

    def children_of(process)
      ProcTable.ps.select { |p| p.ppid == process.pid }
    end

    def report_metric_check_debug(metricname, metrictype, metricvalue)
      if "#{self.debug}" == "true"
        puts("Component/#{metricname}[#{metrictype}] : #{metricvalue}")
      else
        report_metric metricname, metrictype, metricvalue
      end
    end

  end

  NewRelic::Plugin::Setup.install_agent :process_monitor, self
  NewRelic::Plugin::Run.setup_and_run
end