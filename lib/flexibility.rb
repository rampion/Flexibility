# {include:file:README.md}
module Flexibility

  # helper for creating UnboundMethods
  GET_UNBOUND_METHOD = begin
    count = 0 
    lambda do |klass, body|
      klass.class_eval do
        name = "#unbound_method_#{count += 1}"
        define_method(name, &body)
        um = instance_method(name)
        remove_method(name)
        um
      end
    end
  end

  # `#default` allows you to specify a default value for an argument.
  #
  # You can pass `#default` either
  #
  #   - an argument containing a constant value
  #   - a block to be bound to the instance and run as needed
  #
  # With the block form, not only do you have access to instance variables,
  # but you also have access to
  #
  #   - the keyword associated with the argument
  #   - the hash of options defined thus far
  #   - the original argument value (if an earlier transformation `nil`'ed it out)
  #   - the block bound to the method invocation
  #
  # For example, given the method `dimensions`:
  #
  # ```ruby
  # class Banner
  #   include Flexibility
  #
  #   define :dimensions, {
  #     depth:    default( 1 ),
  #     width:    default { @width },
  #     height:   default { |_key,opts| opts[:width] } ,
  #     duration: default { |&blk| blk[] if blk }
  #   } do |opts|
  #     opts
  #   end
  #
  #   def initialize
  #     @width = 40
  #   end
  # end
  # ```
  #
  # We can specify (or not) any of the arguments to see the defaults in action
  #
  #     irb> banner = Banner.new
  #     irb> banner.dimensions
  #     => { depth: 1, width: 40, height: 40, duration: nil }
  #     irb> banner.dimensions( depth: 2, width: 10, height: 5, duration: 7 )
  #     => { depth: 2, width: 10, height: 5, duration: 7 }
  #     irb> banner.dimensions( width: 10 ) { puts "getting duration" ; 12 }
  #     getting duration
  #     => { depth: 1, width: 10, height: 10, duration: 12 }
  #
  # Note that the `yield` keyword inside the block bound to `default` won't be
  # able to access the block bound to the method invocation, as `yield` is
  # lexically scoped (like a local variable).
  #
  # ```ruby
  # module YieldExample
  #   def self.create
  #     Class.new do
  #       include Flexibility
  #       define :run, {
  #         using_yield:  default { yield },
  #         using_block:  default { |&blk| blk[] }
  #       } { |opts| opts }
  #     end.new
  #   end
  # end
  # ```
  #
  #     irb> YieldExample.create { :class_creation }.run { :method_invocation }
  #     => { using_yield: :class_creation, using_block: :method_invocation }
  #
  def default(*args,&cb)
    if args.length != (cb ? 0 : 1)
      raise(ArgumentError, "Wrong number of arguments to `default` (expects 0 with a block, or 1 without)", caller)
    elsif cb
      um = GET_UNBOUND_METHOD[self, cb]
      proc { |val, *args, &blk| val.nil? ? um.bind(self).call(*args.take(um.arity < 0 ? args.length : um.arity),&blk) : val }
    else
      default = args.first
      proc { |val| val.nil? ? default : val }
    end
  end
  def required
    proc do |val,key|
      if val.nil?
        raise(ArgumentError, "Required argument #{key.inspect} not given", caller)
      end
      val
    end
  end
  def validate
    proc do |*args|
      val, key, _opts, orig = *args
      unless yield(*args)
        raise(ArgumentError, "Invalid value #{orig.inspect} given for argument #{key.inspect}", caller)
      end
      val
    end
  end
  def transform(&blk)
    blk
  end

  # private class instance methods?
  def define method_name, expected, &method_body
    if method_body.arity < 0
      raise(NotImplementedError, "Flexibility doesn't support splats in method definitions yet, sorry!", caller)
    elsif method_body.arity > expected.length + 1
      raise(ArgumentError, "More positional arguments in method body than specified in expected arguments", caller)
    end
    
    # create an UnboundMethod from method_body so we can
    # 1. set `self`
    # 2. pass it arguments
    # 3. pass it a block
    #
    # `instance_eval` only allows us to do (1), whereas `instance_exec` only
    # allows (1) and (2), and `call` only allows (2) and (3).
    method_um = GET_UNBOUND_METHOD[self, method_body]

    # similarly, create UnboundMethods from the callbacks
    expected_ums = {}

    expected.each do |key, cbs|
      # normalize a single callback to a collection
      cbs = [cbs] unless cbs.respond_to? :inject

      expected_ums[key] = cbs.map.with_index do |cb, index|
        if UnboundMethod === cb
          cb
        elsif cb.respond_to? :to_proc
          GET_UNBOUND_METHOD[self, cb]
        else
          raise(ArgumentError, "Unrecognized expectation #{cb.inspect} for #{key.inspect}, expecting an UnboundMethod or something that responds to #to_proc", caller)
        end
      end
    end
      
    # assume all but the last block argument should capture positional
    # arguments
    keys = expected_ums.keys[ 0 ... method_um.arity - 1]

    # interpret user arguments using #options, then pass them to the method
    # body
    define_method(method_name) do |*given, &blk|

      # let the caller bundle arguments in a trailing Hash
      trailing_opts = Hash === given.last ? given.pop : {}
      unless expected_ums.length >= given.length
        raise(ArgumentError, "Got #{given.length} arguments, but only know how to handle #{expected_ums.length}", caller)
      end

      opts = trailing_opts.dup
      expected_ums.each.with_index do |(key, ums), i|
        # check positional argument for value first, then default to trailing options
        found = i < given.length ? given[i] : trailing_opts[key]

        # run every callback, threading the results through each
        opts[key] = ums.inject(found) do |val, um|
          um.bind(self).call( *[val, key, opts, found].take(um.arity < 0 ? 4 : um.arity), &blk )
        end
      end

      method_um.bind(self).call(
        *keys.map { |key| opts.delete key }.push( opts ).take( method_um.arity ), &blk
      )
    end
  end

  class <<self
    def append_features(target)
      class<<target
        Flexibility.instance_methods.each do |name|
          define_method(name, Flexibility.instance_method(name))
          private name
        end
      end
    end
  end
end
