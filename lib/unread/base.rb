module Unread
  def self.included(base)
    base.extend Base
  end

  module Base
    def acts_as_reader(options = {})
      resource_name = table_name.singularize.to_sym
      model = DynamicModel.define_model(resource_name)

      model.belongs_to resource_name, class_name: self.to_s

      has_many :read_marks, dependent: :delete_all,
                            foreign_key: "#{resource_name}_id",
                            inverse_of: resource_name,
                            class_name: model.to_s

      define_singleton_method :read_mark_model do
        model
      end

      after_create do |resource|
        # We assume that a new user should not be tackled by tons of old messages
        # created BEFORE he signed up.
        # Instead, the new user starts with zero unread messages
        (model.readable_classes || []).each do |klass|
          klass.mark_as_read!(:all, for: resource)
        end
      end

      model.reader_class = self
      model.reader_options = options

      include Unread::Reader::InstanceMethods
    end

    def acts_as_readable(options = {})
      class_attribute :readable_options

      options.reverse_merge!(on: :updated_at)
      self.readable_options = options

      unread_tables = ActiveRecord::Base.connection.tables.select do |table_name|
        /.*_read_marks\z/ === table_name
      end

      unread_tables.each do |table_name|
        resource_name = table_name.sub("_read_marks", "")
        model = DynamicModel.define_model(resource_name)

        has_many table_name.to_sym, as: :readable,
                                    dependent: :delete_all,
                                    class_name: model.to_s

        model.readable_classes ||= []
        model.readable_classes << self unless model.readable_classes.include?(self)
      end

      include Readable::InstanceMethods
      extend Readable::ClassMethods
      extend Readable::Scopes
    end
  end
end
