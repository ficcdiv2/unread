module Unread
  module Readable
    module ClassMethods
      def mark_as_read!(target, options)
        raise ArgumentError unless options.is_a?(Hash)

        reader = options[:for]
        assert_reader(reader)

        if target == :all
          reset_read_marks_for_user(reader)
        elsif target.is_a?(Array)
          mark_array_as_read(target, reader)
        else
          raise ArgumentError
        end
      end

      def mark_array_as_read(array, reader)
        read_mark = reader.class.read_mark_model
        singularize_reader = reader.class.table_name.singularize.to_sym

        read_mark.transaction do
          global_timestamp = reader.read_mark_global(self).try(:timestamp)

          array.each do |obj|
            raise ArgumentError unless obj.is_a?(self)
            timestamp = obj.send(readable_options[:on])

            if global_timestamp && global_timestamp >= timestamp
              # The object is implicitly marked as read, so there is nothing to do
            else
              rm = obj.read_marks(reader).where("#{singularize_reader}_id" => reader.id).first_or_initialize
              rm.timestamp = timestamp
              rm.save!
            end
          end
        end
      end

      # A scope with all items accessable for the given user
      # It's used in cleanup_read_marks! to support a filtered cleanup
      # Should be overriden if a user doesn't have access to all items
      # Default: User has access to all items and should read them all
      #
      # Example:
      #   def Message.read_scope(user)
      #     user.visible_messages
      #   end
      def read_scope(reader)
        self
      end

      def cleanup_read_marks!
        read_mark_models.each do |model|
          assert_reader_class(model)

          model.reader_scope.find_each do |reader|
            model.transaction do
              if oldest_timestamp = read_scope(reader).unread_by(reader).minimum(readable_options[:on])
                # There are unread items, so update the global read_mark for this user to the oldest
                # unread item and delete older read_marks
                update_read_marks_for_user(reader, oldest_timestamp)
              else
                # There is no unread item, so deletes all markers and move global timestamp
                reset_read_marks_for_user(reader)
              end
            end
          end
        end
      end

      def update_read_marks_for_user(reader, timestamp)
        # Delete markers OLDER than the given timestamp
        reader.read_marks.where(readable_type: base_class.name).single.older_than(timestamp).delete_all

        # Change the global timestamp for this user
        rm = reader.read_mark_global(self) || reader.read_marks.build(readable_type: base_class.name)
        rm.timestamp = timestamp - 1.second
        rm.save!
      end

      def reset_read_marks_for_all
        ReadMark.transaction do
          ReadMark.delete_all :readable_type => self.base_class.name
          ReadMark.connection.execute <<-EOT
            INSERT INTO #{ReadMark.table_name} (user_id, readable_type, timestamp)
            SELECT #{ReadMark.reader_class.primary_key}, '#{self.base_class.name}', '#{Time.current.to_s(:db)}'
            FROM #{ReadMark.reader_class.table_name}
          EOT
        end
      end

      def reset_read_marks_for_user(reader)
        assert_reader(reader)

        read_mark = reader.class.read_mark_model
        singularize_reader = reader.class.table_name.singularize.to_sym

        read_mark.transaction do
          read_mark.delete_all(readable_type: self.base_class.name, "#{singularize_reader}_id" => reader.id)
          read_mark.create!(readable_type: self.base_class.name, "#{singularize_reader}_id" => reader.id, timestamp: Time.current)
        end
      end

      def assert_reader(reader)
        assert_reader_class(reader.class.read_mark_model)

        unless reader.is_a?(reader.class.read_mark_model.reader_class)
          raise ArgumentError, "Class #{reader.class.name} is not registered by acts_as_reader."
        end

        unless reader.id
          raise ArgumentError, "The given user has no id."
        end
      end

      def assert_reader_class(read_mark_model)
        raise RuntimeError, 'There is no class using acts_as_reader.' unless read_mark_model.reader_class
      end
    end

    module InstanceMethods
      def unread?(reader)
        if self.respond_to?(:read_mark_id)
          # For use with scope "with_read_marks_for"
          return false if self.read_mark_id

          if global_timestamp = user.read_mark_global(self.class).try(:timestamp)
            self.send(readable_options[:on]) > global_timestamp
          else
            true
          end
        else
          self.class.unread_by(reader).exists?(self.id)
        end
      end

      def mark_as_read!(options)
        reader = options[:for]
        self.class.assert_reader(reader)

        reader.class.read_mark_model.transaction do
          if unread?(reader)
            rm = read_mark(reader) || read_marks(reader).build("#{singularize_reader_name(reader)}_id".to_sym => reader.id)
            # readableとなるクラスが更新された直後に `#mark_as_read!` を飛び出すと
            # `self` が古い状態のレコードを取得してしまうため、既読状態にならない。
            # そのためselfを呼び出すとき `reload` して最新の状態のレコードを取得する
            rm.timestamp = self.reload.send(readable_options[:on])
            rm.save!
          end
        end
      end

      def read_mark(reader)
        read_marks(reader).where("#{singularize_reader_name(reader)}_id".to_sym => reader.id).first
      end

      def read_marks(reader)
        send("#{singularize_reader_name(reader)}_read_marks")
      end

      private

      def singularize_reader_name(reader)
        reader.class.table_name.singularize.to_sym
      end
    end
  end
end
