module Twilio
  module TwiML
    class ValidationError < StandardError ; end

    def self.parse(xml)
      if xml.class == String
        require 'rexml/document'
        doc = REXML::Document.new(xml).root
        if doc.nil?
          raise ValidationError, "Unparseable XML: #{xml.inspect}"
        end
      else
        doc = xml
      end

      begin
        klass = eval(doc.name)
        raise NameError unless klass.include? Twilio::Verb
      rescue NameError
        raise ValidationError, "Invalid element/class: #{klass}"
      end

      verb = klass.new
      doc.attributes.each do |k,v|
        # Validate attributes
        begin
          verb.send(k+'=',v)
        rescue Exception => e
          raise ValidationError, "Unacceptable attribute: \"#{k}\" = \"#{v}\""
        end
      end

      # if children
      if doc.has_elements?
        if verb.children_prohibited?
          raise ValidationError, "Children prohibited for #{verb.verb_name}"
        end

        verb.instance_eval do
          @children ||= []
          doc.each_element do |e|
            if verb.allowed_verbs.include? e.name
              # process elements recursively
              @children << Twilio::TwiML.parse(e)
            else
              raise ValidationError, "Invalid element: #{e.name}"
            end
          end
        end

      # if body
      elsif doc.has_text? and doc.text.strip != ""
        if verb.body_prohibited?
          raise ValidationError, "Body prohibited for #{verb.verb_name}"
        end

        verb.instance_eval { @body = doc.text }
      end

      verb
    end
  end

  module Verb
    module ClassMethods
      def ClassMethods.extended(other)
        other.set_defaults
      end

      def set_defaults
        @attributes = []
        @allowed_verbs = []
        @policy = { :body => :optional, :children => :optional }
      end

      def allowed_verbs(*verbs)
        return @allowed_verbs if verbs == []

        verbs.each do |verb|
          @allowed_verbs << verb.to_s.capitalize
        end
        @allowed_verbs = @allowed_verbs.uniq
      end

      def attributes(*attrs)
        return @attributes if attrs == []

        @attributes = (@attributes + attrs).uniq
        attr_writer(*@attributes)
        @attributes.each do |attr|
          define_method attr do
            return instance_variable_get("@#{attr.to_s}") || default_attributes[attr]
          end
        end
        @attributes
      end

      def default_attributes
        # TODO Set up method of storing default attributes from the class definitions
        # TODO Validate attribute names and raise error during class definition
        @default_attributes || {}
      end

      def nesting(policy={})
        if policy == :prohibited
          @policy[:body] = policy
          @policy[:children] = policy
          return
        end

        case policy[:body]
          when :required, :optional
            @policy[:body] = policy[:body]
            class_eval "def body; @body ; end
            def body=(str); @body = str ; end"

          when :prohibited
            @policy[:body] = policy[:body]

          else
            raise ArgumentError, "Only :required, :optional, and :prohibited are allowed policies"
        end

        case policy[:children]
          when :required, :optional
            @policy[:children] = policy[:children]
            class_eval "def children ; @children ; end
            def children=(ary) ; @children = ary ; end"

          when :prohibited
            @policy[:children] = policy[:children]

          else
            raise ArgumentError, "Only :required, :optional, and :prohibited are allowed policies"
        end
      end

      def body_required? ; @policy[:body] == :required ; end
      def body_optional? ; @policy[:body] == :optional ; end
      def body_prohibited? ; @policy[:body] == :prohibited ; end

      def children_required? ; @policy[:children] == :required ; end
      def children_optional? ; @policy[:children] == :optional ; end
      def children_prohibited? ; @policy[:children] == :prohibited ; end

      def verb_name
        self.to_s.split(/::/)[-1]
      end
    end

    def allowed_verbs
      self.class.allowed_verbs
    end

    def attributes
      self.class.attributes
    end

    # Default attributes for this Verb
    def default_attributes
      self.class.default_attributes
    end

    # Hash of attributes set for this Verb (not including defaults)
    def valid_attributes
      attributes.inject({}){|h,k| (v=self.send(k)) ? h.merge({k=>v}) : h }
    end

    # Merge valid_attributes with default_attributes
    def merged_attributes
      self.default_attributes.merge(self.valid_attributes);
    end

    def allowed?(verb)
      self.class.allowed_verbs.nil? ? false : self.class.allowed_verbs.include?(verb.to_s.capitalize)
    end

    def body_required?        ; self.class.body_required?       ; end
    def body_optional?        ; self.class.body_optional?       ; end
    def body_prohibited?      ; self.class.body_prohibited?     ; end

    def children_required?    ; self.class.children_required?   ; end
    def children_optional?    ; self.class.children_optional?   ; end
    def children_prohibited?  ; self.class.children_prohibited? ; end

    def verb_name
      self.class.verb_name
    end

    def initialize(body = nil, params = {}, &block)
      @children = []
      if body.class == String
        @body = body
      else
        @body = nil
        params = body || {}
      end
      #default_attributes.each do |k,v|
        #send(k.to_s+"=",v)
      #end
      params.each do |k,v|
        if respond_to? k.to_s+"="
          send(k.to_s+"=",v)
        else
          raise ArgumentError, "Invalid parameter (#{k}) for verb (#{self.class})"
        end
      end

      if block_given? and children_prohibited?
        raise ArgumentError, "#{self.class} isn't allowed to have children"
      end

      yield self if block_given?
    end

    def to_str
      self.to_xml()
    end
    alias :to_s :to_str

    def to_xml(options = {})
      require 'builder' unless defined?(Builder)
      options[:indent] ||= 2
      xml = options[:builder] ||= Builder::XmlMarkup.new(options)
      xml.instruct! unless options[:skip_instruct]
      options[:skip_instruct] = true

      attrs = {}
      attributes.each {|a| attrs[a] = send(a) unless send(a).nil? } unless attributes.nil?

      if not @children.empty? and @body.nil?
        xml.tag!(verb_name, attrs) do
          @children.each {|e| e.to_xml(options) }
        end

      elsif @body and @children.empty?
        xml.tag!(verb_name, @body, attrs)

      elsif @body.nil? and @children.empty?
        xml.tag!(verb_name, attrs)

      else
        raise ArgumentError, "Cannot have children and a body at the same time"
      end
    end


    ##### Verb Convenience Methods #####
    def say(string_to_say, opts = {})
      return unless allowed? :say
      @children << Twilio::Say.new(string_to_say, opts)
      @children[-1]
    end
    alias :Say :say

    def play(file_to_play, opts = {})
      return unless allowed? :play
      @children << Twilio::Play.new(file_to_play, opts)
      @children[-1]
    end
    alias :Play :play

    def gather(opts = {}, &block)
      return unless allowed? :gather
      @children << Twilio::Gather.new(opts)
      yield @children[-1] if block_given?
      @children[-1]
    end
    alias :Gather :gather

    def record(opts = {})
      return unless allowed? :record
      @children << Twilio::Record.new(opts)
      @children[-1]
    end
    alias :Record :record

    def dial(number = "", opts = {})
      return unless allowed? :dial
      @children << Twilio::Dial.new(number, opts)
      yield @children[-1] if block_given?
      @children[-1]
    end
    alias :Dial :dial

    def redirect(url, opts = {})
      return unless allowed? :redirect
      @children << Twilio::Redirect.new(url, opts)
      @children[-1]
    end
    alias :Redirect :redirect

    def pause(opts = {})
      return unless allowed? :pause
      @children << Twilio::Pause.new(opts)
      @children[-1]
    end
    alias :Pause :pause

    def hangup
      return unless allowed? :hangup
      @children << Twilio::Hangup.new
      @children[-1]
    end
    alias :Hangup :hangup

    def number(number, opts = {})
      return unless allowed? :number
      @children << Twilio::Number.new(number, opts)
      @children[-1]
    end
    alias :Number :number
  end

  class Say
    extend Twilio::Verb::ClassMethods
    include Twilio::Verb
    attributes :voice, :language, :loop
    nesting :body => :required, :children => :prohibited
    @default_attributes = { :loop => 1, :language => 'en', :voice => 'man' }
  end

  class Play
    extend Twilio::Verb::ClassMethods
    include Twilio::Verb
    attributes :loop
    nesting :body => :required, :children => :prohibited
    @default_attributes = { :loop => 1 }
  end

  class Gather
    extend Twilio::Verb::ClassMethods
    include Twilio::Verb
    attributes :action, :method, :timeout, :finishOnKey, :numDigits
    allowed_verbs :play, :say, :pause
    nesting :body => :prohibited, :children => :optional
    @default_attributes = { :method => 'POST', :timeout => 30, :numDigits => 1, :finishOnKey => '#' }
  end

  class Record
    extend Twilio::Verb::ClassMethods
    include Twilio::Verb
    attributes :action, :method, :timeout, :finishOnKey, :maxLength, :transcribe, :transcribeCallback
    nesting :prohibited
    @default_attributes = { :method => 'POST', :timeout => 5, :finishOnKey => "1234567890*#", :maxLength => 60 }
  end

  class Dial
    extend Twilio::Verb::ClassMethods
    include Twilio::Verb
    attributes :action, :method, :timeout, :hangupOnStar, :timeLimit, :callerId
    allowed_verbs :number
    nesting :body => :optional, :children => :optional
    @default_attributes = { :method => 'POST', :timeout => '30', :hangupOnStar => false, :timeLimit => '60' }
  end

  class Redirect
    extend Twilio::Verb::ClassMethods
    include Twilio::Verb
    attributes :method
    nesting :body => :required, :children => :prohibited
    @default_attributes = { :method => 'POST' }
  end

  class Pause
    extend Twilio::Verb::ClassMethods
    include Twilio::Verb
    attributes :length
    nesting :prohibited
    @default_attributes = { :length => 1 }
  end

  class Hangup
    extend Twilio::Verb::ClassMethods
    include Twilio::Verb
    nesting :prohibited
  end

  class Number
    extend Twilio::Verb::ClassMethods
    include Twilio::Verb
    attributes :sendDigits, :url
    nesting :body => :required, :children => :prohibited
    @default_attributes = { :sendDigits => '', :url => '' }
  end

  class Response
    extend Twilio::Verb::ClassMethods
    include Twilio::Verb
    allowed_verbs :say, :play, :gather, :record, :dial, :redirect, :pause, :hangup
    nesting :body => :prohibited, :children => :optional
  end

  module ControllerHooks
    def add_hook(hook, name, code)
      session[:twilio_hooks] ||= {}
      session[:twilio_hooks][hook] ||= {}
      session[:twilio_hooks][hook][name] = code
      return nil
    end

    def remove_hook(hook, name)
      session[:twilio_hooks] ||= {}
      session[:twilio_hooks][hook] ||= {}
      session[:twilio_hooks][hook].delete(name) if session[:twilio_hooks][hook][name]
      return nil
    end

    def run_hook(hook)
      session[:twilio_hooks] ||= {}
      session[:twilio_hooks][hook] ||= {}
      session[:twilio_hooks][hook].each{|name,code| 
        RAILS_DEFAULT_LOGGER.debug "Running hook '#{name}'"
        eval(code)
      }
      return nil
    end
  end
end
