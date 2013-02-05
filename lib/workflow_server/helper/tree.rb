module Tree
  include Colorize

  def tree(big_tree = false)
    child_trees = get_child_trees(big_tree)
    child_trees.empty? ? node(big_tree) : node(big_tree).merge(children: child_trees)
  end

  def big_tree
    tree(true)
  end

  def print_tree(to_string = false)
    string = spacer + color_code(to_s_for_tree) + "\n"
    get_children.each do |child|
      string += child.print_tree(true)
    end
    to_string ? string : (puts string)
  end

  private

  def depth
    @depth ||= self.parent.nil? ? 0 : self.parent.depth + 1
  end

  def node(big_tree = false)
    big_tree ? serializable_hash : {id: self.id, type: event_type, name: self.name, status: self.status}
  end

  def get_children
    self.children
  end

  def get_child_trees(big_tree = false)
    child_trees = []
    get_children.each do |child|
      child_trees << child.tree(big_tree)
    end
    child_trees
  end

  def to_s_for_tree
    "#{event_type.capitalize}:#{self.name} is #{self.status}.\t ID -> #{self.id}"
  rescue
    self.to_s
  end

  def spacer
    if depth > 1
      cyan("#{('   ' * (depth - 2))}\|--")
    else
      cyan('*--')
    end
  end

  def color_code(text)
    case self[:status]
    when :executing, :running_sub_activity, :waiting_for_sub_activities
      yellow(text)
    when :complete
      green(text)
    when :error, :errored, :failed, :timeout
      red(text)
    else
      text
    end
  end

end
