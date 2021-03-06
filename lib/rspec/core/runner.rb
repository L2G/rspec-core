module RSpec
  module Core
    class Runner

      # Register an at_exit hook that runs the suite.
      def self.autorun
        return if autorun_disabled? || installed_at_exit? || running_in_drb?
        at_exit do
          # Don't bother running any specs and just let the program terminate
          # if we got here due to an unrescued exception (anything other than
          # SystemExit, which is raised when somebody calls Kernel#exit).
          next unless $!.nil? || $!.kind_of?(SystemExit)

          # We got here because either the end of the program was reached or
          # somebody called Kernel#exit.  Run the specs and then override any
          # existing exit status with RSpec's exit status if any specs failed.
          status = run(ARGV, $stderr, $stdout).to_i
          exit status if status != 0
        end
        @installed_at_exit = true
      end
      AT_EXIT_HOOK_BACKTRACE_LINE = "#{__FILE__}:#{__LINE__ - 2}:in `autorun'"

      def self.disable_autorun!
        @autorun_disabled = true
      end

      def self.autorun_disabled?
        @autorun_disabled ||= false
      end

      def self.installed_at_exit?
        @installed_at_exit ||= false
      end

      def self.running_in_drb?
        defined?(DRb) &&
        (DRb.current_server rescue false) &&
         DRb.current_server.uri =~ /druby\:\/\/127.0.0.1\:/
      end

      def self.trap_interrupt
        trap('INT') do
          exit!(1) if RSpec.wants_to_quit
          RSpec.wants_to_quit = true
          STDERR.puts "\nExiting... Interrupt again to exit immediately."
        end
      end

      # Run a suite of RSpec examples.
      #
      # This is used internally by RSpec to run a suite, but is available
      # for use by any other automation tool.
      #
      # If you want to run this multiple times in the same process, and you
      # want files like spec_helper.rb to be reloaded, be sure to load `load`
      # instead of `require`.
      #
      # #### Parameters
      # * +args+ - an array of command-line-supported arguments
      # * +err+ - error stream (Default: $stderr)
      # * +out+ - output stream (Default: $stdout)
      #
      # #### Returns
      # * +Fixnum+ - exit status code (0/1)
      def self.run(args, err=$stderr, out=nil)
        trap_interrupt
        options = ConfigurationOptions.new(args)
        options.parse_options

        # If out is undefined, the default is normally $stdout. The
        # exception is Windows without ANSICON installed. In that case,
        # Win32::Console::ANSI::IO must be used to intercept ANSI control
        # strings and translate them to the Windows console API.
        #
        # NOTE: We don't have to worry about the corner case where the user
        # asked for color AND has Win32::Console BUT is redirecting output;
        # Win32::Console is supposed to handle that gracefully.

        out = nil if out == $stdout
        if out.nil?
          if options.options[:color] and RSpec.windows_os? and !ENV['ANSICON']
            begin
              require 'Win32/Console/ANSI'
              out = Win32::Console::ANSI::IO.open
            rescue LoadError
              warn "Color output on Windows is supported with one of these installed:\n" +
                   "* win32console (Ruby gem)\n" +
                   "* ANSICON 1.31 or later (https://github.com/adoxa/ansicon)\n" +
                   "But neither one could be found, so this may get messy..."
            end
          end
          # Default for when it's not Windows, or ANSICON is installed, or
          # using Win32::Console failed for whatever reason.
          out ||= $stdout
        end

        if options.options[:drb]
          require 'rspec/core/drb_command_line'
          begin
            DRbCommandLine.new(options).run(err, out)
          rescue DRb::DRbConnError
            err.puts "No DRb server is running. Running in local process instead ..."
            CommandLine.new(options).run(err, out)
          end
        else
          CommandLine.new(options).run(err, out)
        end
      ensure
        RSpec.reset
      end
    end
  end
end
