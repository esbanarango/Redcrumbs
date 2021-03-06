module Redcrumbs
  mattr_accessor :creator_class_sym
  mattr_accessor :creator_primary_key
  mattr_accessor :target_class_sym
  mattr_accessor :target_primary_key

  mattr_accessor :store_creator_attributes
  mattr_accessor :store_target_attributes

  mattr_accessor :mortality
  mattr_accessor :redis

  mattr_accessor :class_name


  # This should only be used to load old crumbs from previous versions
  # of the gem, in future require an explicit creator/target method to set.
  #
  @@creator_class_sym ||= :user
  @@creator_primary_key ||= 'id'
  @@target_class_sym ||= :user 
  @@target_primary_key ||= 'id'

  @@store_creator_attributes ||= []
  @@store_target_attributes ||= []


  # Constantises the class_name attribute, falls back to the Crumb default.
  #
  def self.crumb_class
    if @@class_name and @@class_name.length > 0
      constantize_class_name
    else
      Crumb
    end
  end
  

  # Stolen from resque. Thanks!
  # Accepts:
  #   1. A 'hostname:port' String
  #   2. A 'hostname:port:db' String (to select the Redis db)
  #   3. A 'hostname:port/namespace' String (to set the Redis namespace)
  #   4. A Redis URL String 'redis://host:port'
  #   5. An instance of `Redis`, `Redis::Client`, `Redis::DistRedis`,
  #      or `Redis::Namespace`.
  #
  def self.redis=(server)
    case server
    when String
      if server =~ /redis\:\/\//
        redis = Redis.connect(:url => server, :thread_safe => true)
      else
        server, namespace = server.split('/', 2)
        host, port, db = server.split(':')
        redis = Redis.new(:host => host, :port => port,
          :thread_safe => true, :db => db)
      end
      namespace ||= :redcrumbs

      @@redis = Redis::Namespace.new(namespace, :redis => redis)
    when Redis::Namespace
      @@redis = server
    else
      @@redis = Redis::Namespace.new(:redcrumbs, :redis => server)
    end

    setup_datamapper!

    @@redis
  end

  private

  # Note: Since it's not possible to access the exact connection the DataMapper adapter
  # uses we have to use the @@redis module variable and make sure it's consistent.
  #
  def self.setup_datamapper!
    adapter = DataMapper.setup(:default, 
      { :adapter  => "redis", 
        :host => self.redis.client.host, 
        :port => self.redis.client.port, 
        :password => self.redis.client.password
      })

    # For supporting namespaces:
    #
    adapter.resource_naming_convention = lambda do |value|
      inflected_value = DataMapper::Inflector.pluralize(DataMapper::Inflector.underscore(value)).gsub('/', '_')

      "#{self.redis.namespace}:#{inflected_value}"
    end
  end

  def self.constantize_class_name
    klass = @@class_name.to_s.classify.constantize

    unless klass < Redcrumbs::Crumb
      raise ArgumentError, 'Redcrumbs crumb_class must inherit from Redcrumbs::Crumb'
    end

    klass
  rescue NameError
    Crumb
  end
end