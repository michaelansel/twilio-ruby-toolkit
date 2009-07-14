require 'active_record'

class DatabaseMutex < ActiveRecord::Base
  def self.create_table!
    return false if table_exists?

    table_name = self.table_name()
    self.connection.instance_eval do

      create_table table_name do |col|
        col.text    :session_id,  :null => false
      end
      add_timestamps table_name
      add_index table_name, :session_id

    end

    reset_column_information
    return table_exists?
  end

  def self.drop_table!
    return false unless table_exists?

    self.connection.drop_table( self.table_name )

    return table_exists?
  end

  def self.locked?(*args)
    uncached do
      exists?(*args)
    end
  end
end
