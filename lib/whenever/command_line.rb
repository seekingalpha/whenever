require 'fileutils'
require 'whenever/cron_parser'
require 'whenever/capistrano/v2/support'

module Whenever
  class CommandLine
    def self.execute(options={})
      new(options).run
    end

    def initialize(options={})
      @options = options

      @options[:file]       ||= 'config/schedule.rb'
      @options[:cut]        ||= 0
      @options[:identifier] ||= default_identifier

      if !File.exists?(@options[:file]) && @options[:clear].nil?
        warn("[fail] Can't find file: #{@options[:file]}")
        exit(1)
      end

      if [@options[:update], @options[:write], @options[:clear]].compact.length > 1
        warn("[fail] Can only update, write or clear. Choose one.")
        exit(1)
      end

      unless @options[:cut].to_s =~ /[0-9]*/
        warn("[fail] Can't cut negative lines from the crontab #{options[:cut]}")
        exit(1)
      end
      @options[:cut] = @options[:cut].to_i
    end

    def run
      if @options[:update] || @options[:clear]
        write_crontab(updated_crontab)
      elsif @options[:write]
        write_crontab(whenever_cron)
      else
        puts Whenever.cron(@options)
        puts "## [message] Above is your schedule file converted to cron syntax; your crontab file was not updated."
        puts "## [message] Run `whenever --help' for more options."
        exit(0)
      end
    end

  protected

    def default_identifier
      File.expand_path(@options[:file])
    end

    def whenever_cron
      return '' if @options[:clear]
      @whenever_cron ||= [comment_open, Whenever.cron(@options), comment_close].compact.join("\n") + "\n"
    end

    def read_crontab
      return @current_crontab if @current_crontab

      command = ['crontab -l']
      command << "-u #{@options[:user]}" if @options[:user]

      command_results  = %x[#{command.join(' ')} 2> /dev/null]
      @current_crontab = $?.exitstatus.zero? ? prepare(command_results) : ''
    end

    def write_crontab(contents)
      command = ['crontab']
      command << "-u #{@options[:user]}" if @options[:user]
      command << "-"

      IO.popen(command.join(' '), 'r+') do |crontab|
        crontab.write(contents)
        crontab.close_write
      end

      success = $?.exitstatus.zero?

      if success
        action = 'written' if @options[:write]
        action = 'updated' if @options[:update]
        puts "[write] crontab file #{action}"
        trigger_crons(contents)
        exit(0)
      else
        warn "[fail] Couldn't write crontab; try running `whenever' with no options to ensure your schedule file is valid."
        exit(1)
      end
    end

    def updated_crontab
      # Check for unopened or unclosed identifier blocks
      if read_crontab =~ Regexp.new("^#{comment_open}\s*$") && (read_crontab =~ Regexp.new("^#{comment_close}\s*$")).nil?
        warn "[fail] Unclosed indentifier; Your crontab file contains '#{comment_open}', but no '#{comment_close}'"
        exit(1)
      elsif (read_crontab =~ Regexp.new("^#{comment_open}\s*$")).nil? && read_crontab =~ Regexp.new("^#{comment_close}\s*$")
        warn "[fail] Unopened indentifier; Your crontab file contains '#{comment_close}', but no '#{comment_open}'"
        exit(1)
      end

      # If an existing identier block is found, replace it with the new cron entries
      if read_crontab =~ Regexp.new("^#{comment_open}\s*$") && read_crontab =~ Regexp.new("^#{comment_close}\s*$")
        # If the existing crontab file contains backslashes they get lost going through gsub.
        # .gsub('\\', '\\\\\\') preserves them. Go figure.
        read_crontab.gsub(Regexp.new("^#{comment_open}\s*$.+^#{comment_close}\s*$", Regexp::MULTILINE), whenever_cron.chomp.gsub('\\', '\\\\\\'))
      else # Otherwise, append the new cron entries after any existing ones
        [read_crontab, whenever_cron].join("\n\n")
      end.gsub(/\n{3,}/, "\n\n") # More than two newlines becomes just two.
    end

    def prepare(contents)
      # Strip n lines from the top of the file as specified by the :cut option.
      # Use split with a -1 limit option to ensure the join is able to rebuild
      # the file with all of the original seperators in-tact.
      stripped_contents = contents.split($/,-1)[@options[:cut]..-1].join($/)

      # Some cron implementations require all non-comment lines to be newline-
      # terminated. (issue #95) Strip all newlines and replace with the default
      # platform record seperator ($/)
      stripped_contents.gsub!(/\s+$/, $/)
    end

    def trigger_crons(content)
        given_time = Time.now - 4 * 60
        time_marker = Time.now
        need_to_run = {}
        crontent = content.lines.map(&:chomp)
        crontent.delete_if{|line| line.start_with?('#') || line.empty? }

        crontent.each{|line|
          splited_line = line.split(" ")
          cron_time = splited_line.take(5).join(" ")
          puts "Cron line => #{line}"
          puts "Cron time => #{cron_time}"
          cron_parser = CronParser.new(cron_time)
          next_exec = cron_parser.next(given_time)
          need_to_run[next_exec] = splited_line.drop(5)
          puts "|#{line}| will run at #{next_exec}"
          need_to_run.each{|next_t,line_to_run|

            if next_t.utc < time_marker.utc
              puts "Need to run #{line_to_run}"
              #args = {
              #  :command => fetch(:whenever_command),
              #  :flags   => fetch(:whenever_update_flags),
              #  :path    => fetch(:latest_release)
              #}
              #whenever_run_commands
              `#{line_to_run.join(" ")}`
            end
          }
        }
    end

    def comment_base
      "Whenever generated tasks for: #{@options[:identifier]}"
    end

    def comment_open
      "# Begin #{comment_base}"
    end

    def comment_close
      "# End #{comment_base}"
    end
  end
end
