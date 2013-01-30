module Tree

  def tree(big_tree = false)
    child_trees = get_child_trees || []
    child_trees.empty? ? node(big_tree) : node(big_tree).merge(children: child_trees)
  end

  def big_tree
    tree(true)
  end

  private

  def get_child_trees(big_tree = false)
    child_trees = []
    self.children.each do |child|
      child_trees << child.tree(big_tree)
    end
    child_trees
  end

  def node(big_tree = false)
    big_tree ? self.serializable_hash : {id: id, type: event_type, name: name, status: status}
  end

end
