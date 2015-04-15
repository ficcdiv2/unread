module Unread
  module Readable
    module Scopes
      def join_read_marks(resource)
        assert_reader(resource)

        read_mark_table_name = resource.class.read_mark_model.table_name
        joins "LEFT JOIN #{read_mark_table_name} AS read_marks
                 ON  read_marks.readable_type = '#{base_class.name}'
                 AND read_marks.readable_id   = #{table_name}.#{primary_key}
                 AND read_marks.#{resource.class.table_name.singularize}_id = #{resource.id}
                 AND read_marks.timestamp    >= #{table_name}.#{readable_options[:on]}"
      end

      def unread_by(resource)
        result = join_read_marks(resource).where("read_marks.id IS NULL")

        if global_time_stamp = resource.read_mark_global(self).try(:timestamp)
          result = result.where("#{table_name}.#{readable_options[:on]} > ?", global_time_stamp)
        end

        result
      end

      def with_read_marks_for(user)
        join_read_marks(user).select("#{table_name}.*, read_marks.id AS read_mark_id")
      end
    end
  end
end
