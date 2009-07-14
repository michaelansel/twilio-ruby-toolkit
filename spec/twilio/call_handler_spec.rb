require 'twilio/call_handler'

class MockQueue
  def initialize
    @queue = Array.new
  end

  ## Accessors ##
  def to_a
    @queue.dup
  end

  ## Modifiers ##

  def <<(obj)
    @queue << obj
  end

  def clear
    @queue.clear
  end

  def empty?
    @queue.empty?
  end

  def replace(ary)
    @queue.replace(ary)
  end

  def shift
    @queue.shift
  end

  def unshift(obj)
    @queue.unshift
  end
end



describe Twilio::CallHandler do
  before(:each) do
    #MockQueue.should_receive(:<<).with(anything()).any_number_of_times.and_return {|a|a}
    #MockQueue.should_receive(:clear).with(no_args()).any_number_of_times.and_return(true)
    #MockQueue.should_receive(:empty?).with(no_args()).any_number_of_times.and_return(true)
    #MockQueue.should_receive(:replace).with(an_instance_of(Array)).any_number_of_times.and_return {|a|a}
    #MockQueue.should_receive(:shift).with(anything()).any_number_of_times.and_return {|a|a}
    #MockQueue.should_receive(:unshift).with(no_args()).any_number_of_times.and_return({})

    ### Processing Queue "API" ###
    #
    # <<(obj)         Append obj to the end of the queue
    # clear           Remove all objects from the queue
    # empty?          Is the queue completely empty?
    # replace(ary)    Clear the queue and add elements of ary
    # shift           Remove and return the first object in the queue
    # unshift(obj)    Insert obj at the beginning of the queue


    MockQueue.class_eval do
      attr_accessor :queue
    end
    Twilio::CallHandler.class_eval do
      attr_accessor :cookie, :input_status, :input_data, :input_verb, :output_queue, :processing_queue
    end

    @ch = Twilio::CallHandler.new( {:queue_class => MockQueue} )
  end

  describe "in a new state" do
    it "should have an empty processing queue" do
      @ch.processing_queue.should be_empty
    end
    it "should not have an input status" do
      @ch.input_status.should == :none
    end
    it "should not have an input verb" do
      @ch.input_verb.should == nil
    end
    it "should not have any input data" do
      @ch.input_data.should == ""
    end
    it "should not have any cookies" do
      @ch.cookie.should == ""
    end
    it "should have an empty output queue" do
      @ch.output_queue.should be_empty
    end
  end

  describe "processing the queue" do
    it "should pass the next item in the queue to the processor" do
      @ch.processing_queue = mock(MockQueue)

      @ch.processing_queue.stub(:shift).and_return(:process_me, :process_me, nil)
      @ch.processing_queue.stub(:empty?).and_return(:false, :false, :true)

      @ch.should_receive(:process_response).twice.with(:process_me).ordered.and_return(true)
      @ch.should_receive(:process_response).once.with(nil).ordered.and_return(false)

      output = @ch.process_queue
      output.should == [[],true]
    end

    it "should remove the next item in the queue" do
    end
  end
end
