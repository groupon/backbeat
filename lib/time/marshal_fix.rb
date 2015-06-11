############################################## MONKEY-PATCH ################################################
## FIX JRUBY TIME MARSHALLING - SEE https://github.com/rails/rails/issues/10900 ############################
# require 'active_support/core_ext/time/marshal' # add crappy marshalling first and then overwrite it

class Time
  class << self
    alias_method :_load_without_zone, :_load unless method_defined?(:_load_without_zone)
    def _load(marshaled_time)
      time = _load_without_zone(marshaled_time)
      time.instance_eval do
        if isdst_and_zone = defined?(@_isdst_and_zone) && remove_instance_variable('@_isdst_and_zone')
          ary = to_a
          ary[0] += subsec if ary[0] == sec
          ary[-2, 2] = isdst_and_zone
          utc? ? Time.utc(*ary) : Time.local(*ary)
        else
          self
        end
      end
    end
  end

  alias_method :_dump_without_zone, :_dump unless method_defined?(:_dump_without_zone)
  def _dump(*args)
    obj = dup
    obj.instance_variable_set('@_isdst_and_zone', [dst?, zone])
    obj.send :_dump_without_zone, *args
  end
end

############################################### MONKEY-PATCH OVER ############################################
