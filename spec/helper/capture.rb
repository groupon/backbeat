module Capture
  def self.with_out_capture(&block)
    capture = StringIO.new
    out = $stdout
    $stdout = capture
    block.call
    capture.string
  ensure
    $stdout = out
  end
end
