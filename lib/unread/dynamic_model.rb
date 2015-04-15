module Unread
  module DynamicModel
    def self.define_model(resource_name)
      model = "Unread::DynamicModel::#{resource_name.to_s.classify}ReadMark"
      # すでにクラスが定義されていたらそのクラスを返す
      return const_get(model) if const_defined?(model)

      klass = Class.new(ActiveRecord::Base) do
        belongs_to :readable, polymorphic: true

        validates "#{resource_name}_id".to_sym, :readable_type, presence: true

        scope :global, -> { where(readable_id: nil) }
        scope :single, -> { where.not(:readable_id, nil) }
        scope :older_than, -> (timestamp) { where([ 'timestamp < ?', timestamp ]) }

        # Returns the class defined by acts_as_reader
        class_attribute :reader_class
        class_attribute :reader_options

        # Returns the classes defined by acts_as_readable
        class_attribute :readable_classes

        def self.reader_scope
          result = reader_class

          Array(reader_options[:scopes]).each do |scope|
            result = result.send(scope)
          end
          result
        end
      end

      const_set("#{resource_name.to_s.classify}ReadMark", klass)

      klass
    end
  end
end
