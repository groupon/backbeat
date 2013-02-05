module Tree

  def tree(big_tree = false, depth = 0)
    child_trees = get_child_trees(big_tree, depth + 1) || []
    child_trees.empty? ? node(big_tree, depth + 1) : node(big_tree, depth + 1).merge(children: child_trees)
  end

  def big_tree
    tree(true, 0)
  end

  private

  def get_child_trees(big_tree = false, depth = 0)
    child_trees = []
    self.children.each do |child|
      child_trees << child.tree(big_tree, depth)
    end
    child_trees
  end

  def node(big_tree = false, depth = 0)
    big_tree ? Node.new(self.serializable_hash, depth) : Node.new({id: id, type: event_type, name: name, status: status}, depth)
  end

  class Node < Hash
    include Colorize

    attr_accessor :depth

    def initialize(hash, depth)
      hash.each_pair do |key,value|
        self[key.to_sym] = value
      end
      self.depth = depth
    end

    def print(to_string = false)
      string = spacer + color_code(to_s) + "\n"
      if children = self[:children]
        children.each do |child|
          string += child.print(true)
        end
      end
      to_string ? string : (puts string)
    end

    def to_s
      "#{self[:type].capitalize}:#{self[:name]} is #{self[:status]}."
    end

    private

    def spacer
      if self.depth > 1
        cyan("#{('   ' * (self.depth - 2))}\|--")
      else
        cyan('*--')
      end
    end

    def color_code(text)
      case self[:status]
      when :executing, :running_sub_activity, :restarting
        yellow(text)
      when :complete
        green(text)
      when :error, :failed, :timeout
        red(text)
      else
        text
      end
    end

  end
end
