require 'active_record'

class DatabaseQueueItem < ActiveRecord::Base
  serialize :data

  def self.create_table!
    if table_exists?
      puts "Table already exists"
      return false
    end

    dqi = self.table_name()
    self.connection.instance_eval do

      create_table dqi do |col|
        col.text    :session_id,  :null => false
        col.text    :queue_name,  :null => false
        col.integer :queue_index, :null => false
        col.text    :data,        :null => true
      end

      add_timestamps dqi

      add_index dqi, :session_id
      add_index dqi, :queue_name
      add_index dqi, :queue_index
      add_index dqi, [:session_id,:queue_name,:queue_index], :unique => true

    end


    reset_column_information
    return table_exists?
  end

  def self.drop_table!
    unless table_exists?
      puts "Table doesn't exist"
      return false
    end

    self.connection.drop_table( self.table_name )

    return !table_exists?
  end

end

class DatabaseQueue# < Array
  attr_reader :session_id, :queue_name

  def initialize(opts={})
    DatabaseQueueItem.create_table! unless DatabaseQueueItem.table_exists?

    @session_id = opts[:session_id]# if opts.has_key? :session_id
    @queue_name = opts[:queue_name]# if opts.has_key? :queue_name

    raise ArgumentError, "DatabaseQueue needs a session_id!" if @session_id.nil?
    raise ArgumentError, "DatabaseQueue needs a queue_name!" if @queue_name.nil?
  end

  ## Helpers ##
  # Merge conditions
  def c(*args)
    args = args[0] if args.length == 1

    case args
    when Hash
      args = [{:session_id => @session_id , :queue_name => @queue_name}.merge(args)]
    when Array
      args << {:session_id => @session_id , :queue_name => @queue_name}
    when String
      args = [args,{:session_id => @session_id , :queue_name => @queue_name}]
    else
      raise ArgumentError, "I don't know what to do with a #{args.class}"
    end

    DatabaseQueueItem.merge_conditions(*args)
  end
  def find(*args)
    raise StandardError
    unless [:first, :last, :all].include? args.first
      puts "Not filtering by session_id: #{args.inspect}"
      return DatabaseQueueItem.find(args)
    end
    how_many = args.shift
    params = args.shift || {}

    if not args.empty?
      raise ArgumentError, "what do I doooooo? args = #{args.inspect}"
    end

    if params.class == Hash and params.has_key? :conditions
      conditions = DatabaseQueueItem.merge_conditions(
                        params.delete(:conditions), { :session_id => @session_id }, :queue_name => @queue_name )
    else
      conditions = { :session_id => @session_id, :queue_name => @queue_name }
    end

    DatabaseQueueItem.find( how_many,  { :conditions => conditions,
                        :order => "queue_index ASC"
                      }.merge(params)
         )
  end
  def first_item
    DatabaseQueueItem.first(:conditions => c, :order => "queue_index ASC", :limit => 1)
  end
  def last_item
    DatabaseQueueItem.first(:conditions => c, :order => "queue_index DESC", :limit => 1)
  end

  def first_index
    DatabaseQueueItem.minimum(:queue_index, :conditions => c) || 0
  end
  def last_index
    DatabaseQueueItem.maximum(:queue_index, :conditions => c) || 0
  end

  ## Accessors ##
  def length
    DatabaseQueueItem.count(:conditions => c)
  end
  alias :size :length
  def to_s
    to_a.to_s
  end
  def inspect
    to_a.inspect
  end
  def to_yaml(*args)
    to_a.to_yaml(*args)
  end
  def to_a
    DatabaseQueueItem.find(:all, :conditions => c, :order => "queue_index ASC").collect{|dqi| dqi.data}
  end
  alias :to_ary :to_a
  def [](*args)
    if args.length == 1 and args.first >= 0
      return DatabaseQueueItem.find(:all, :conditions => c, :order => "queue_index ASC", :offset => args.first, :limit => 1).first.data
    else
      return to_a[args]
    end
  end
  def include?(obj)
    return (DatabaseQueueItem.count(:conditions => c(:data => obj)) > 0)
  end

  ## Modifiers ##
  def <<(obj)
    DatabaseQueueItem.create!(
      :session_id => @session_id,
      :queue_name => @queue_name,
      :queue_index => (last_index+1),
      :data => obj
    )
    self
  end

  def clear
    DatabaseQueueItem.destroy_all(c)
    self
  end

  def empty?
    length == 0
  end

  def replace(ary)
    clear
    ary.each {|d| self<<(d)}
    self
  end

  def shift
    first_item.destroy.data
  end

  def unshift(obj)
    DatabaseQueueItem.create!(
      :session_id => @session_id,
      :queue_name => @queue_name,
      :queue_index => (first_index-1),
      :data => obj
    )
    self
  end
end

