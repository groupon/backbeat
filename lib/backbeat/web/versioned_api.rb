require 'grape'

class VersionedAPI
  def self.versioned(version = '/')
    Class.new(Grape::API).tap do |klass|
      klass.namespace(version, &@api)
    end
  end

  def self.api(&block)
    @api = block
  end
end
