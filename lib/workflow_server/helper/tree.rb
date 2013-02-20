module Tree

  def tree
    child_trees = get_child_trees
    child_trees.empty? ? Node.new(self) : Node.new(self).merge(children: child_trees)
  end

  def tree_to_s(first_call = true , nodes = [])
    nodes << Node.new(self)
    get_children.each do |child|
      nodes << child.tree_to_s(false, nodes)
    end
    if first_call
      "\n" + nodes.compact.map{|node| node.to_s}.join("\n") + "\n\n"
    end
  end

  def print_tree
    puts tree_to_s
  end

  def depth
    @depth ||= self.parent.nil? ? 1 : self.parent.depth + 1
  end

  private

  def get_children
    self.children
  end

  def get_child_trees
    child_trees = []
    get_children.each do |child|
      child_trees << child.tree
    end
    child_trees
  end

  class Node < Hash
    include Colorize

    def initialize(model)
      merge!({id: model.id, type: model.event_type, name: model.name, status: model.status})
      @depth = model.depth
    end

    def to_s
      self[:id].to_s + spacer + color_code("#{self[:type].capitalize}:#{self[:name]} is #{self[:status]}.")
    end

    private

    def spacer
      cyan("#{('   ' * @depth)}\|--")
    end

    def color_code(text)
      case self[:status]
      when :executing, :running_sub_activity, :waiting_for_sub_activities
        yellow(text)
      when :complete
        green(text)
      when :error, :failed, :timeout
        red(text)
      else
        white(text)
      end
    end

  end


end
