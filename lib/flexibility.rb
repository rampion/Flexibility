# {include:file:README.md}
#
# @author Noah Luck Easterly <noah.easterly@gmail.com>
module Flexibility

  # helper for creating UnboundMethods
  #
  #     irb> inject = Array.instance_method(:inject)
  #     irb> Flexibility::RUN_UNBOUND_METHOD.(inject, %w{ a b c }, "x") { |l,r| "(#{l}#{r})" }
  #     => "(((xa)b)c)"
  #     irb> inject_r = Flexibility::DEF_UNBOUND_METHOD.( Array ) { |*args,&blk| reverse.inject(*args, &blk) }
  #     irb> Flexibility::RUN_UNBOUND_METHOD.(inject_r, %w{ a b c }, "x") { |l,r| "(#{l}#{r})" }
  #     => "(((xc)b)a)"
  #
  DEF_UNBOUND_METHOD = begin
    count = 0
    lambda do |klass, &body|
      klass.class_eval do
        name = "#unbound_method_#{count += 1}"
        define_method(name, &body)
        um = instance_method(name)
        remove_method(name)
        um
      end
    end
  end

  # helper to call UnboundMethods with proper number of args
  #
  #     irb> def self.show_error ; yield ; rescue => e ; [ e.class, e.message ] ; end
  #     irb> each = Array.instance_method(:each)
  #     irb> show_error { each.bind( [ 1, 2, 3] ).call( 4, 5, 6 ) { |x| puts x } }
  #     => [ ArgumentError, "wrong number of arguments (3 for 0)" ]
  #     irb> show_error { Flexibility::RUN_UNBOUND_METHOD.(each, [ 1, 2, 3], 4, 5, 6 ) { |x| puts x } }
  #     1
  #     2
  #     3
  #     => [1,2,3]
  #
  RUN_UNBOUND_METHOD = lambda do |um, instance, *args, &blk|
    args = args.take(um.arity) if 0 <= um.arity && um.arity < args.length
    um.bind(instance).call(*args,&blk)
  end

  # @!group Argument Callback Generators

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
  # @param value
  #   to be returned by returned `UnboundMethod` if it is given `nil` as first parameter
  # @yield
  #   remaining arguments and block given to returned `UnboundMethod`,
  #   called if it was given `nil` as first parameter
  #   (bound to same value of `self` as returned proc)
  # @yieldreturn
  #   to be returned by returned `UnboundMethod`
  # @raise  [ArgumentError]
  #   if given too many arguments
  # @return [UnboundMethod]
  #   `UnboundMethod` which returns first parameter given if non-`nil`,
  #   otherwise yields to block bound to `#default` or returns parameter given
  #   to `#default`
  # @see #define
  def default(*args,&cb)
    if args.length != (cb ? 0 : 1)
      raise(ArgumentError, "Wrong number of arguments to `default` (expects 0 with a block, or 1 without)", caller)
    elsif cb
      um = DEF_UNBOUND_METHOD[self, &cb]
      DEF_UNBOUND_METHOD.(self) do |*args, &blk| 
        val = args.shift
        unless val.nil? 
          val
        else
          RUN_UNBOUND_METHOD[um,self,*args,&blk]
        end
      end
    else
      default = args.first
      DEF_UNBOUND_METHOD.(self) { |*args| val = args.shift; val.nil? ? default : val }
    end
  end

  # @return [UnboundMethod]
  #   `UnboundMethod` which returns first parameter given if non-`nil`,
  #   otherwise raises `ArgumentError`
  # @see #define
  def required
    DEF_UNBOUND_METHOD.(self) do |*args|
      val, key = *args
      if val.nil?
        raise(ArgumentError, "Required argument #{key.inspect} not given", caller)
      end
      val
    end
  end

  # @yield
  #   arguments and block given to returned `UnboundMethod`,
  #   (bound to same value of `self` as returned proc)
  # @yieldreturn [Boolean]
  #   indicates whether the returned `UnboundMethod` should
  #   return the first parameter or raise an `ArgumentError`.
  # @return [UnboundMethod]
  #   `UnboundMethod` which returns first parameter given if block
  #   bound to `#validate` returns truthy on arguments/block given ,
  #   raises `ArgumentError` otherwise.
  # @see #define
  def validate(&cb)
    um = DEF_UNBOUND_METHOD[self, &cb]
    DEF_UNBOUND_METHOD.(self) do |*args,&blk|
      val, key, _opts, orig = *args
      unless RUN_UNBOUND_METHOD[um,self,*args,&blk]
        raise(ArgumentError, "Invalid value #{orig.inspect} given for argument #{key.inspect}", caller)
      end
      val
    end
  end

  # @yield
  #   arguments and block given to returned `UnboundMethod`,
  #   (bound to same value of `self` as returned proc)
  # @yieldreturn
  #   value for returned `UnboundMethod` to return
  # @return [UnboundMethod]
  #   `UnboundMethod` created from block bound to `#transform`
  # @see #define
  def transform(&blk)
    DEF_UNBOUND_METHOD.(self, &blk)
  end

  # @!endgroup

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
    method_um = DEF_UNBOUND_METHOD[self, &method_body]

    # similarly, create UnboundMethods from the callbacks
    expected_ums = {}

    expected.each do |key, cbs|
      # normalize a single callback to a collection
      cbs = [cbs] unless cbs.respond_to? :inject

      expected_ums[key] = cbs.map.with_index do |cb, index|
        if UnboundMethod === cb
          cb
        elsif cb.respond_to? :to_proc
          DEF_UNBOUND_METHOD[self, &cb]
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
          RUN_UNBOUND_METHOD[um, self, val, key, opts, found, &blk]
        end
      end

      RUN_UNBOUND_METHOD[ 
        method_um, 
        self, 
        *keys.map { |key| opts.delete key }.push( opts ).take( method_um.arity ), 
        &blk 
      ]
    end
  end

  # When included, `Flexibility` adds all its instance methods as private class
  # methods of the including class:
  #
  #     irb> c = Class.new 
  #     irb> before = c.private_methods
  #     irb> c.class_eval { include Flexibility }
  #     irb> c.private_methods - before
  #     => [ :default, :required, :validate, :transform, :define ]
  #
  # @param target [Module] the class or module that included Flexibility
  # @see Module#include
  def self.append_features(target)
    class<<target
      Flexibility.instance_methods.each do |name|
        define_method(name, Flexibility.instance_method(name))
        private name
      end
    end
  end
end
