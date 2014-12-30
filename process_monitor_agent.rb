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

        missing_processes = 0

        processes.each do |search|
          rss = 0
          percent_memory = 0
          percent_cpu = 0
          uptime = 0
          pids = Array.new

          process_list = ProcTable.ps.select { |p| p.cmdline.include?(search) }
          process_list.each do |process|
            uptime = uptime_of(process) if process['ppid'] == 1
            pids << pid_of(process)
            rss = rss + rss_of(process)
            percent_memory = percent_memory + percent_memory_of(process)
            percent_cpu = percent_cpu + percent_cpu_of(process)
            children = children_of(process)
            children.each do |child|
              pids << pid_of(child)
              rss = rss + rss_of(child)
              percent_memory = percent_memory + percent_memory_of(child)
              percent_cpu = percent_cpu + percent_cpu_of(child)
            end
          end

          report_metric_check_debug("Process/#{search}/process count", 'count', pids.compact.uniq.count)
          report_metric_check_debug("Process/#{search}/rss", 'bytes', rss)
          report_metric_check_debug("Process/#{search}/percent cpu", 'percentage', percent_cpu)
          report_metric_check_debug("Process/#{search}/percent memory", 'percentage', percent_memory)
          report_metric_check_debug("Process/#{search}/uptime", "seconds", uptime)

          missing_processes += 1 if pids.empty?
        end

        report_metric_check_debug('Missing Process/count', 'count', missing_processes)

      rescue => e
        $stderr.puts "#{e}: #{e.backtrace.join("\n   ")}"
      end
    end

    def uptime_of(process)
      Time.now.to_i - Time.at(File.stat("/proc/#{process['pid']}/stat").ctime).to_i if process['ppid'] == 1
    end

    def pid_of(process)
      process['pid'] or 1
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