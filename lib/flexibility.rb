# {include:file:README.md}
#
# @author Noah Luck Easterly <noah.easterly@gmail.com>
module Flexibility

  # helper for creating UnboundMethods
  #
  #     irb> inject = Array.instance_method(:inject)
  #     irb> Flexibility.run_unbound_method(inject, %w{ a b c }, "x") { |l,r| "(#{l}#{r})" }
  #     => "(((xa)b)c)"
  #     irb> inject_r = Flexibility.create_unbound_method( Array ) { |*args,&blk| reverse.inject(*args, &blk) }
  #     irb> Flexibility.run_unbound_method(inject_r, %w{ a b c }, "x") { |l,r| "(#{l}#{r})" }
  #     => "(((xc)b)a)"
  #
  # in a less civilized time, I might have just monkey-patched this as
  # `UnboundMethod::create`
  def self.create_unbound_method(klass, &body)
    name = body.inspect
    klass.class_eval do
      define_method(name, &body)
      um = instance_method(name)
      remove_method(name)
      um
    end
  end

  # helper to call UnboundMethods with proper number of args
  #
  #     irb> def self.show_error ; yield ; rescue => e ; [ e.class, e.message ] ; end
  #     irb> each = Array.instance_method(:each)
  #     irb> show_error { each.bind( [ 1, 2, 3] ).call( 4, 5, 6 ) { |x| puts x } }
  #     => [ ArgumentError, "wrong number of arguments (3 for 0)" ]
  #     irb> show_error { Flexibility.run_unbound_method(each, [ 1, 2, 3], 4, 5, 6 ) { |x| puts x } }
  #     1
  #     2
  #     3
  #     => [1,2,3]
  #
  # in a less civilized time, I might have just monkey-patched this as
  # `UnboundMethod#run`
  def self.run_unbound_method(um, instance, *args, &blk)
    args = args.take(um.arity) if 0 <= um.arity && um.arity < args.length
    um.bind(instance).call(*args,&blk)
  end

  # @!group Argument Callback Generators

  # {#default} allows you to specify a default value for an argument.
  #
  # You can pass {#default} either
  #
  #   - an argument containing a constant value
  #   - a block to be bound to the instance and run as needed
  #
  # With the block form, you also have access to
  #
  #   - `self` and the instance variables of the bound instance
  #   - the keyword associated with the argument
  #   - the hash of options defined thus far
  #   - the original argument value (useful if an earlier transformation `nil`'ed it out)
  #   - the block bound to the method invocation
  #
  # For example, given the method `dimensions`:
  #
  # ```ruby
  # class Banner
  #   include Flexibility
  #
  #   define( :dimensions,
  #     depth:    default( 1 ),
  #     width:    default { @width },
  #     height:   default { |_key,opts| opts[:width] } ,
  #     duration: default { |&blk| blk[] if blk }
  #   ) do |opts|
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
  #       define( :run,
  #         using_yield:  default { yield },
  #         using_block:  default { |&blk| blk[] }
  #       ) { |opts| opts }
  #     end.new
  #   end
  # end
  # ```
  #
  #     irb> YieldExample.create { :class_creation }.run { :method_invocation }
  #     => { using_yield: :class_creation, using_block: :method_invocation }
  #
  # @param default_val
  #   if the returned `UnboundMethod` is called with `nil` as its first parameter,
  #   it returns `default_val` (unless {#default} is called with a block)
  # @yield
  #   if the returned `UnboundMethod` is called with `nil` as its first parameter,
  #   it returns the result of `yield` (unless {#default} is called with an
  #   argument).
  #
  #   The block bound to {#default} receives the following parameters when called
  #   by a method created with {#define}:
  # @yieldparam key     [Symbol]  the key of the option currently being processed
  # @yieldparam opts    [Hash]    the options hash thus far
  # @yieldparam initial [Object]  the original value passed to the method for this option
  # @yieldparam &blk    [Proc]    the block passed to the method
  # @yieldparam self    [keyword] bound to the same instance that the method is invoked on
  # @raise  [ArgumentError]
  #   unless called with a block and no args, or called with no block and one arg
  # @return [UnboundMethod(val,key,opts,initial,&blk)]
  # @see #define
  # @!parse def default(default_val) ; end
  def default(*args,&cb)
    if args.length != (cb ? 0 : 1)
      raise(ArgumentError, "Wrong number of arguments to `default` (expects 0 with a block, or 1 without)", caller)
    elsif cb
      um = Flexibility::create_unbound_method(self, &cb)
      Flexibility::create_unbound_method(self) do |*args, &blk| 
        val = args.shift
        unless val.nil? 
          val
        else
          Flexibility::run_unbound_method(um,self,*args,&blk)
        end
      end
    else
      default = args.first
      Flexibility::create_unbound_method(self) { |*args| val = args.shift; val.nil? ? default : val }
    end
  end

  # {#required} allows you to throw an exception if an argument is not given.
  #
  # {#required} returns an `UnboundMethod` that simply checks that its first
  # parameter is non-`nil`:
  #
  #   - if the parameter is `nil`, it raises an `ArgumentError`
  #   - if the parameter is not `nil`, it returns it.
  #
  # For example, 
  #
  # ```ruby
  # class Banner
  #   include Flexibility
  #
  #   define( :area,
  #     width: required,
  #     height: required
  #   ) do |width,height,_| 
  #     width * height
  #   end
  # end
  # ```
  #
  # We can specify (or not) any of the arguments to see the checking in action
  #
  #     irb> def self.show_error ; yield ; rescue => e ; [ e.class, e.message ] ; end
  #     irb> banner = Banner.new
  #     irb> show_error { banner.area }
  #     => [ ArgumentError, "Required argument :width not given" ]
  #     irb> show_error { banner.area :width => 5 }
  #     => [ ArgumentError, "Required argument :height not given" ]
  #     irb> show_error { banner.area :height => 5 }
  #     => [ ArgumentError, "Required argument :width not given" ]
  #     irb> show_error { banner.area :width => 6, :height => 5 }
  #     => 30
  #
  # Note that {#required} specifically checks that the argument is non-nil, not
  # *unspecified*, so explicitly given `nil` arguments will still raise an
  # error:
  #
  #     irb> show_error { banner.area :width => nil, :height => 5 }
  #     => [ ArgumentError, "Required argument :width not given" ]
  #
  # @return [UnboundMethod(val,key,opts,initial,&blk)]
  #   `UnboundMethod` which returns first parameter given if non-`nil`,
  #   otherwise raises `ArgumentError`
  # @see #define
  def required
    Flexibility::create_unbound_method(self) do |*args|
      val, key = *args
      if val.nil?
        raise(ArgumentError, "Required argument #{key.inspect} not given", caller)
      end
      val
    end
  end

  # {#validate} allows you to throw an exception if the given block returns
  # falsy.
  #
  # You pass {#validate} a block which will be invoked each time the
  # returned `UnboundMethod` is called.
  #
  #   - if the block returns true, the `UnboundMethod` will return the first parameter
  #   - if the block returns false, the `UnboundMethod` will raise an `ArgumentError`
  #
  # Within the block, you have access to
  #
  #   - `self` and the instance variables of the bound instance
  #   - the keyword associated with the argument
  #   - the hash of options defined thus far
  #   - the original argument value (useful if an earlier transformation `nil`'ed it out)
  #   - the block bound to the method invocation
  #
  # For example, given the method ``:
  #
  # ```ruby
  # class Converter
  #   include Flexibility
  #
  #   define( :polar_to_cartesian,
  #     radius: validate { |r| 0 <= r },
  #     theta:  validate { |t| 0 <= t && t < Math::PI },
  #     phi:    validate { |p| 0 <= p && p < 2*Math::PI }
  #   ) do |r,t,p,_|
  #     { x: r * Math.sin(t) * Math.cos(p), 
  #       y: r * Math.sin(t) * Math.sin(p),
  #       z: r * Math.cos(t)
  #     }
  #   end
  # end
  # ```
  #
  #     irb> def self.show_error ; yield ; rescue => e ; [ e.class, e.message ] ; end
  #     irb> conv = Converter.new
  #     irb> show_error { conv.polar_to_cartesian -1, 0, 0 }
  #     => [ ArgumentError, "Invalid value -1 given for argument :radius" ]
  #     irb> show_error { conv.polar_to_cartesian 0, -1, 0 }
  #     => [ ArgumentError, "Invalid value -1 given for argument :theta" ]
  #     irb> show_error { conv.polar_to_cartesian 0, 0, -1 }
  #     => [ ArgumentError, "Invalid value -1 given for argument :phi" ]
  #     irb> show_error { conv.polar_to_cartesian 0, 0, 0 }
  #     => { x: 0, y: 0, z: 0 }
  #
  #
  # And just to show how you can access instance variables,
  # earlier parameters, and the bound block with {#validate}...
  #
  # ```ruby
  # class Silly
  #   include Flexibility
  #
  #   def initialize(min,max)
  #     @min,@max = min,max
  #   end
  #
  #   in_range = validate { |x,&blk| @min <= blk[x] && blk[x] <= @max }
  #
  #   define( :check,
  #     lo:     in_range,
  #     hi:     [ 
  #       in_range, 
  #       validate { |x,key,opts,&blk| blk[opts[:lo]] <= blk[x] } 
  #     ],
  #   ) { |opts| opts }
  # end
  # ```
  #
  #     irb> silly = Silly.new(3,5)
  #     irb> show_error { silly.check("hi", "salutations") { |s| s.length } }
  #     => [ ArgumentError, 'Invalid value "hi" given for argument :lo' ]
  #     irb> show_error { silly.check("hey", "salutations") { |s| s.length } }
  #     => [ ArgumentError, 'Invalid value "salutations" given for argument :hi' ]
  #     irb> show_error { silly.check("hello", "hey") { |s| s.length } }
  #     => [ ArgumentError, 'Invalid value "hey" given for argument :hi' ]
  #     irb> show_error { silly.check("hey", "hello") { |s| s.length } }
  #     => { lo: "hey", hi: "hello" }
  #
  # Note that the `yield` keyword inside the block bound to {#validate} won't be
  # able to access the block bound to the method invocation, as `yield` is
  # lexically scoped (like a local variable).
  #
  # ```ruby
  # module YieldExample
  #   def self.create
  #     Class.new do
  #       include Flexibility
  #       define( :run,
  #         using_yield:  validate { |val,key|      puts [key, yield].inspect ; true },
  #         using_block:  validate { |val,key,&blk| puts [key, blk[]].inspect ; true }
  #       ) { |opts| opts }
  #     end.new
  #   end
  # end
  # ```
  #
  #     irb> YieldExample.create { :class_creation }.run(1,2) { :method_invocation }
  #     [:using_yield, :class_creation]
  #     [:using_block, :method_invocation]
  #     => { using_yield: 1, using_block: 2 }
  #
  # @yield
  #   The block bound to {#validate} receives the following parameters when
  #   called by a method created with {#define}:
  # @yieldparam val     [Object]  the value of the option currently being processed
  # @yieldparam key     [Symbol]  the key for the option currently being processed
  # @yieldparam opts    [Hash]    the options hash thus far
  # @yieldparam initial [Object]  the original value passed to the method for this option
  # @yieldparam &blk    [Proc]    the block passed to the method
  # @yieldparam self    [keyword] bound to the same instance that the method is invoked on
  # @yieldreturn [Boolean]
  #   indicates whether the returned `UnboundMethod` should
  #   return the first parameter or raise an `ArgumentError`.
  # @return [UnboundMethod(val,key,opts,initial,&blk)]
  #   `UnboundMethod` which returns first parameter given if block
  #   bound to {#validate} returns truthy on arguments/block given ,
  #   raises `ArgumentError` otherwise.
  # @see #define
  def validate(&cb)
    um = Flexibility::create_unbound_method(self, &cb)
    Flexibility::create_unbound_method(self) do |*args,&blk|
      val, key, _opts, orig = *args
      unless Flexibility::run_unbound_method(um,self,*args,&blk)
        raise(ArgumentError, "Invalid value #{orig.inspect} given for argument #{key.inspect}", caller)
      end
      val
    end
  end

  # {#transform} allows you to lift an arbitrary code block into an
  # `UnboundMethod`.
  #
  # You pass {#transform} a block which will be invoked each time the returned
  # `UnboundMethod` is called.  Within the block, you have access to
  #
  #   - `self` and the instance variables of the bound instance
  #   - the keyword associated with the argument
  #   - the hash of options defined thus far
  #   - the original argument value (useful if an earlier transformation `nil`'ed it out)
  #   - the block bound to the method invocation
  #
  # The return value of the `UnboundMethod` will be completely determined by the
  # return value of the block bound to the call of {#transform}.
  #
  # ```ruby
  # require 'date'
  # class Timer
  #   include Flexibility
  #
  #   to_epoch = transform do |t|
  #     case t
  #     when String   ; DateTime.parse(t).to_time.to_i
  #     when DateTime ; t.to_time.to_i
  #     else          ; t.to_i if t.respond_to? :to_i
  #     end
  #   end
  #
  #   define( :elapsed,
  #     start: to_epoch,
  #     stop:  to_epoch
  #   ) do |start, stop, _|
  #     stop - start
  #   end
  # end
  # ```
  #
  #     irb> timer = Timer.new
  #     irb> timer.elapsed "1984-06-07", "1989-06-16"
  #     => 158544000
  #     irb> (timer.elapsed DateTime.now, (DateTime.now + 365)) / 60
  #     => 525600
  #
  # And just to show how you can access instance variables,
  # earlier parameters, and the bound block with {#transform}...
  #
  # ```ruby
  # class Silly
  #   include Flexibility
  #
  #   def initialize base
  #     @base = base
  #   end
  #
  #   define( :tag_with_base,
  #     fst:  transform { |x,&blk|   [x, blk[@base] ]      },
  #     snd:  transform { |x,_,opts| [x, opts[:fst].last] }
  #   ) { |opts| opts }
  # end
  # ```
  #
  #     irb> silly = Silly.new( "base value" )
  #     irb> silly.tag_with_base( fst: 3, snd: "hi" ) { |msg| puts msg ; msg.length }
  #     base value
  #     => { fst: [ 3, 10 ], snd: [ "hi", 10 ] }
  #     
  #
  # Note that the `yield` keyword inside the block bound to {#transform} won't be
  # able to access the block bound to the method invocation, as `yield` is
  # lexically scoped (like a local variable).
  #
  # ```ruby
  # module YieldExample
  #   def self.create
  #     Class.new do
  #       include Flexibility
  #       define( :run,
  #         using_yield:  transform { |val|      yield(val) },
  #         using_block:  transform { |val,&blk| blk[val] }
  #       ) { |opts| opts }
  #     end.new
  #   end
  # end
  # ```
  #
  #     irb> YieldExample.create { |val| [:class_creation, val] }.run(1,2) { |val| [ :method_invocation, val] }
  #     => { using_yield: [:class_creation, 1], using_block: [:method_invocation,2] }
  #
  # @yield
  #   The block bound to {#transform} receives the following parameters when
  #   called by a method created with {#define}:
  # @yieldparam val     [Object]  the value of the option currently being processed
  # @yieldparam key     [Symbol]  the key for the option currently being processed
  # @yieldparam opts    [Hash]    the options hash thus far
  # @yieldparam initial [Object]  the original value passed to the method for this option
  # @yieldparam &blk    [Proc]    the block passed to the method
  # @yieldparam self    [keyword] bound to the same instance that the method is invoked on
  # @yieldreturn
  #   value for returned `UnboundMethod` to return
  # @return [UnboundMethod(val,key,opts,initial,&blk)]
  #   `UnboundMethod` created from block bound to {#transform}
  # @see #define
  def transform(&blk)
    Flexibility::create_unbound_method(self, &blk)
  end

  # @!endgroup

  # 
  # @param method_name [Symbol]
  # @param expected    [Hash]
  # @yield 
  # @see #default
  # @see #required
  # @see #validate
  # @see #transform
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
    method_um = Flexibility::create_unbound_method(self, &method_body)

    # similarly, create UnboundMethods from the callbacks
    expected_ums = {}

    expected.each do |key, cbs|
      # normalize a single callback to a collection
      cbs = [cbs] unless cbs.respond_to? :inject

      expected_ums[key] = cbs.map.with_index do |cb, index|
        if UnboundMethod === cb
          cb
        elsif cb.respond_to? :to_proc
          Flexibility::create_unbound_method(self, &cb)
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
        initial = i < given.length ? given[i] : trailing_opts[key]

        # run every callback, threading the results through each
        opts[key] = ums.inject(initial) do |val, um|
          Flexibility::run_unbound_method(um, self, val, key, opts, initial, &blk)
        end
      end

      Flexibility::run_unbound_method(
        method_um, 
        self, 
        *keys.map { |key| opts.delete key }.push( opts ).take( method_um.arity ), 
        &blk 
      )
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
