module Color
  def self.colorize(text, color_code)
    "#{color_code}#{text}\e[0m"
  end

  def self.red(text)
    colorize(text, "\e[31m")
  end

  def self.green(text)
    colorize(text, "\e[32m")
  end
end

module Groupon
  module FinancialEngineering
    module Capistrano
      def self.get_confirmation(confirm_string = "hell yes", reason = "do something dangerous")
        $stdout.sync = true
        puts "You are asking to #{reason}."
        puts "Are you sure you want to do this?"
        print "If yes, please type #{confirm_string}: "
        answer = STDIN.gets.chomp

        unless answer == confirm_string
          puts "You said ('#{answer}') -- aborting!"
          exit 1
        end
      end
    end
  end
end
