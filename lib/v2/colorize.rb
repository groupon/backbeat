module Colorize

  def colorize(text, color_code)
    "\e[#{color_code}m#{text}\e[0m"
  end

  colors = {black:     30,
            red:       31,
            green:     32,
            yellow:    33,
            blue:      34,
            magenta:   35,
            cyan:      36,
            white:     37
           }

  colors.each_pair do |color, number|
    send :define_method, color do |text|
      colorize(text, number)
    end
  end

end
