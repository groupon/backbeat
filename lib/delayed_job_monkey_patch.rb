class Delayed::Worker
  def name
     @name ||=  "#{@name_prefix}host:#{Socket.gethostname} pid:#{Process.pid} tid:#{Thread.current.object_id}"
  end
end
