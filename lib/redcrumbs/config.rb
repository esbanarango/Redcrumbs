module Redcrumbs
  mattr_accessor :creator_class_sym
  mattr_accessor :creator_primary_key
  mattr_accessor :target_class_sym
  mattr_accessor :target_primary_key

  mattr_accessor :store_creator_attributes
  mattr_accessor :store_target_attributes

  mattr_accessor :mortality
  
  @@creator_class_sym ||= [:user]
  @@creator_primary_key ||= [:id]
  @@target_class_sym ||= [:user]
  @@target_primary_key ||= [:id]
end