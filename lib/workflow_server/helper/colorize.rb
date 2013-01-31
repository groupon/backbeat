module Colorize

  def colorize(text, color_code)
    "\e[#{color_code}m#{text}\e[0m"
  end

  colors = {red: 31,
            yellow: 33,
            green: 32,
            cyan: 36}

  colors.each_pair do |color, number|
    send :define_method, color do |text|
      colorize(text, number)
    end
  end

end
