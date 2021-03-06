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
  #
  # ----
  #
  # @param klass  [Class]  class to associate the method with
  # @param body   [Proc]   proc to use for the method body
  # @return [UnboundMethod]
  def self.create_unbound_method(klass, &body)
    name = body.inspect
    klass.class_eval do
      define_method(name, &body)
      um = instance_method(name)
      remove_method(name)
      um
    end
  end

  # helper to call UnboundMethods with proper number of args,
  # and avoid `ArgumentError: wrong number of arguments`.
  #
  #     irb> each = Array.instance_method(:each)
  #     irb> each.bind( [ 1, 2, 3] ).call( 4, 5, 6 ) { |x| puts x }
  #     !> ArgumentError: wrong number of arguments (3 for 0)
  #     irb> Flexibility.run_unbound_method(each, [ 1, 2, 3], 4, 5, 6 ) { |x| puts x }
  #     1
  #     2
  #     3
  #     => [1,2,3]
  #
  # in a less civilized time, I might have just monkey-patched this as
  # `UnboundMethod#run`
  #
  # ----
  #
  # @param um       [UnboundMethod(*args,blk) => res]
  #                           UnboundMethod to run
  # @param instance [Object]  object to bind `um` to, must be a instance of `um.owner`
  # @param args     [Array]   arguments to pass to invocation of `um`
  # @param blk      [Proc]    block to bind to invocation of `um`
  # @return [res]
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
  #     => { depth: 1, width: 40, height: 40 }
  #     irb> banner.dimensions( depth: 2, width: 10, height: 5, duration: 7 )
  #     => { depth: 2, width: 10, height: 5, duration: 7 }
  #     irb> banner.dimensions( width: 10 ) { puts "getting duration" ; 12 }
  #     getting duration
  #     => { depth: 1, width: 10, height: 10, duration: 12 }
  #
  # ----
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
  # ----
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
  # @!parse def default(default_val=nil) ; end
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
  #     irb> banner = Banner.new
  #     irb> banner.area
  #     !> ArgumentError: Required argument :width not given
  #     irb> banner.area :width => 5
  #     !> ArgumentError: Required argument :height not given
  #     irb> banner.area :height => 5
  #     !> ArgumentError: Required argument :width not given
  #     irb> banner.area :width => 6, :height => 5
  #     => 30
  #
  # Note that {#required} specifically checks that the argument is non-nil, not
  # *unspecified*, so explicitly given `nil` arguments will still raise an
  # error:
  #
  #     irb> banner.area :width => nil, :height => 5
  #     !> ArgumentError: Required argument :width not given
  #
  # ----
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
  #     irb> conv = Converter.new
  #     irb> conv.polar_to_cartesian -1, 0, 0
  #     !> ArgumentError: Invalid value -1 given for argument :radius
  #     irb> conv.polar_to_cartesian 0, -1, 0
  #     !> ArgumentError: Invalid value -1 given for argument :theta
  #     irb> conv.polar_to_cartesian 0, 0, -1
  #     !> ArgumentError: Invalid value -1 given for argument :phi
  #     irb> conv.polar_to_cartesian 0, 0, 0
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
  #     irb> silly.check("hi", "salutations") { |s| s.length }
  #     !> ArgumentError: Invalid value "hi" given for argument :lo
  #     irb> silly.check("hey", "salutations") { |s| s.length }
  #     !> ArgumentError: Invalid value "salutations" given for argument :hi
  #     irb> silly.check("hello", "hey") { |s| s.length }
  #     !> ArgumentError: Invalid value "hey" given for argument :hi
  #     irb> silly.check("hey", "hello") { |s| s.length }
  #     => { lo: "hey", hi: "hello" }
  #
  # ----
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
  # ----
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
  # ----
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
  # ----
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

  # {#define} lets you define methods that can be called with either
  #
  #   - positional arguments
  #   - keyword arguments
  #   - a mix of positional and keyword arguments
  #
  # It takes a `method_name`, an `Hash` using the argument keywords as keys,
  # and a block defining the method body.
  #
  # For example
  #
  # ```ruby
  # class Example
  #   include Flexibility
  #
  #   define( :run,
  #     a: [],
  #     b: [],
  #     c: []
  #   ) do |opts|
  #     opts.each { |k,v| puts "#{k}: #{v.inspect}" }
  #   end
  #
  # end
  # ```
  #
  #     irb> ex = Example.new
  #     irb> ex.run( 1, 2, 3 )  # all positional arguments
  #     a: 1
  #     b: 2
  #     c: 3
  #     irb> ex.run( c:1, a:2, b:3, d: 0 ) # all keyword arguments
  #     a: 2
  #     b: 3
  #     c: 1
  #     d: 0
  #     irb> ex.run( 7, 9, d: 18, c:11 ) # mixed keyword and positional arguments
  #     a: 7
  #     b: 9
  #     c: 11
  #     d: 18
  #
  # Positional arguments will override keyword arguments if both are given
  #
  #     irb> ex.run( 10, 20, 30, a: 1, b: 2, c: 3 )
  #     a: 10
  #     b: 20
  #     c: 30
  #
  # By default, `nil` or unspecified values won't appear in the options hash
  # given to the method body.
  #
  #     irb> ex.run( nil, a: 2, c: 3 )
  #     c: 3
  #
  # You can use as many keyword arguments as you like, but calling the method
  # with extra positional arguments will cause the method to raise an exception
  #
  #     irb> ex.run( 1, 2, 3, 4 )
  #     !> ArgumentError: Got 4 arguments, but only know how to handle 3
  #
  # ----
  #
  # {#define} also lets you decide whether the method body receives the arguments
  #
  #   - in a Hash
  #   - as a mix of positional arguments and a trailing hash
  #
  # It does this by inspecting the arity of the block that defines the method
  # body. A block that takes `N+1` arguments will be provided with `N`
  # positional arguments.  The final argument to the block is always a hash of
  # options.
  #
  # For example:
  #
  # ```ruby
  # class Example
  #   include Flexibility
  #
  #   define( :run,
  #     a: [],
  #     b: [],
  #     c: []
  #   ) do |a,b,opts|
  #     puts "a    = #{a.inspect}"
  #     puts "b    = #{b.inspect}"
  #     puts "opts = #{opts.inspect}"
  #     opts.length
  #   end
  # end
  # ```
  #
  #     irb> ex.run( 1, 2, 3 )
  #     a    = 1
  #     b    = 2
  #     opts = {:c=>3}
  #     irb> ex.run( a:1, b:2, c:3, d:4 )
  #     a    = 1
  #     b    = 2
  #     opts = {:c=>3, :d=>4}
  #
  # If the method body takes too many arguments (more than the number of
  # keywords plus one for the options hash), then {#define} will raise an error
  # instead of creating the method, since it lacks keywords to use to refer to
  # those extra arguments
  #
  #     irb> Class.new { include Flexibility ; define(:ex) { |a,b,c,opts| } }
  #     !> ArgumentError: More positional arguments in method body than specified in expected arguments
  #
  # Currently, it's also an error to give {#define} a method body that uses a
  # splat (`*`) to capture a variable number of arguments:
  #
  #     irb> Class.new { include Flexibility ; define(:ex) { |*args,opts| } }
  #     !> NotImplementedError: Flexibility doesn't support splats in method definitions yet, sorry!
  #
  # ----
  #
  # {#define} also lets you specify, along with each keyword, a sequence of
  # UnboundMethod callbacks to be run on the argument given for that keyword on
  # each run of the generated method.
  #
  # When run, these callbacks will be passed:
  #
  #   - the current value of the given argument
  #   - the keyword associated with the given argument
  #   - the hash of options generated thus far
  #   - the original value of the given argument
  #   - any block passed to this invocation of the generated method
  #
  # The callback will also have its value of `self` bound to the same instance
  # running the generated method.
  #
  # ```ruby
  # class IntParser
  #   include Flexibility
  #
  #   def initialize base
  #     @base = base
  #   end
  #
  #   def parse arg
  #     arg.to_i(@base)
  #   end
  #
  #   define(:parse_both,
  #     a: [ instance_method(:parse) ],
  #     b: [ instance_method(:parse) ]
  #   ) do |opts|
  #     opts
  #   end
  # end
  # ```
  #
  #     irb> p16 = IntParser.new(16)
  #     irb> p32 = IntParser.new(32)
  #     irb> p16.parse_both *%w{ ff 11 }
  #     => { a: 255, b: 17 }
  #     irb> p32.parse_both *%w{ ff 11 }
  #     => { a: 495, b: 33 }
  #
  # If you pass multiple callbacks, they are executed in sequence, with the
  # result of one callback being fed to the next:
  #
  # ```ruby
  # class IntParser
  #   #...
  #   def increment num
  #     num + 1
  #   end
  #
  #   def decrement num
  #     num - 1
  #   end
  #
  #   def format arg
  #     arg.to_s(@base)
  #   end
  #
  #   define(:parse_change_and_format_both,
  #     a: [ instance_method(:parse), instance_method(:increment), instance_method(:format) ],
  #     b: [ instance_method(:parse), instance_method(:decrement), instance_method(:format) ],
  #   ) do |opts|
  #     opts
  #   end
  # end
  # ```
  #
  #     irb> p16.parse_change_and_format_both *%w{ ff 11 }
  #     => { a: "100", b: "10" }
  #     irb> p32.parse_change_and_format_both *%w{ ff 11 }
  #     => { a: "fg", b: "10" }
  #
  # Rather than defining one-off instance methods like `IntParser#increment` and
  # `IntParser#decrement`, you can use the {#default}, {#required},
  # {#transform}, and {#validate} methods provided by `Flexibility` to construct
  # `UnboundMethod` callbacks:
  #
  # ```ruby
  # class IntParser
  #   #...
  #   parse = instance_method(:parse)
  #   format = instance_method(:format)
  #
  #   parsable = validate do |s|
  #     _0 = '0'.ord
  #     _9 = _0 + [@base, 10].min - 1
  #     _a = 'a'.ord
  #     _z = _a + [@base - 10, 26].min - 1
  #     _A = 'A'.ord
  #     _Z = _A + [@base - 10, 26].min - 1
  #     s.chars.all? do |c|
  #       n = c.ord
  #       [ _0 <= n && n <= _9,
  #         _a <= n && n <= _z,
  #         _A <= n && n <= _Z,
  #       ].any?
  #     end
  #   end
  #
  #   define(:parse_change_and_format_both,
  #     a: [ parsable, parse, transform { |i| i + 1 }, format ],
  #     b: [ parsable, parse, transform { |i| i - 1 }, format ],
  #   ) do |opts|
  #     opts
  #   end
  # end
  # ```
  #
  #     irb> p16.parse_change_and_format_both *%w{ ff 11 }
  #     => { a: "100", b: "10" }
  #     irb> p16.parse_change_and_format_both *%w{ gg 11 }
  #     !> ArgumentError: Invalid value "gg" given for argument :a
  #     irb> p32.parse_change_and_format_both *%w{ gg 11 }
  #     => { a: "gh", b: "10" }
  #
  # To make it even simpler, you can also use a `Proc`, `Symbol` or
  # anything else that responds to `#to_proc` for a callback as well.
  #
  # ```ruby
  # class Item
  #   def initialize foo, bar
  #     @foo, @bar = foo, bar
  #   end
  #   def foo(*args)
  #     puts "running foo! with #{args.inspect}"
  #     @foo
  #   end
  #   def bar(*args)
  #     puts "running bar! with #{args.inspect}"
  #     @bar
  #   end
  #   def inspect
  #     "#<Item @foo=#@foo @bar=#@bar>"
  #   end
  # end
  #
  # class Example
  #   include Flexibility
  #   def initialize tag
  #     @tag = tag
  #   end
  #
  #   define(:run,
  #     a: [ :foo, proc { |n,&blk| blk[ @tag, n ] } ],
  #     b: [ :bar, proc { |n,&blk| blk[ @tag, n ] } ]
  #   ) do |opts|
  #     opts
  #   end
  # end
  # ```
  #
  #     irb> item = Item.new( "left", "right" )
  #     irb> ex   = Example.new( "popcorn" )
  #     irb> ex.run( a: item, b: item ) { |tag, val| puts "running block with tag=#{tag} val=#{val}" ; tag + val }
  #     running foo! with [:a, {}, #<Item @foo=left @bar=right>]
  #     running block with tag=popcorn val=left
  #     running bar! with [:b, {:a=>"popcornleft"}, #<Item @foo=left @bar=right>]
  #     running block with tag=popcorn val=right
  #     => { a: "popcornleft", b: "popcornright" }
  #
  # Note how, as mentioned earler, we can access the bound block and prior
  # options within the callback.
  #
  # In addition, if you only need a single callback for an argument, you don't
  # have to wrap it in an array:
  #
  # ```ruby
  # class Example
  #
  #   def initialize(min)
  #     @min = min
  #   end
  #
  #   define(:run,
  #     foo:  required,
  #     bar:  validate { |bar| bar >= @min },
  #     baz:  default { |_,opts| opts[:bar] },
  #     quux: transform { |val,key| val[key] }
  #   ) do |opts|
  #     opts
  #   end
  # end
  # ```
  #
  #     irb> ex = Example.new(10)
  #     irb> ex.run
  #     !> ArgumentError: Required argument :foo not given
  #     irb> ex.run 100, 0
  #     !> ArgumentError: Invalid value 0 given for argument :bar
  #     irb> ex.run 100, 17, quux: { quux: 5 }
  #     => { foo: 100, bar: 17, baz: 17, quux: 5 }
  #
  # ----
  #
  # The method body given to {#define} can receive the block bound to the
  # method call at runtime using the standard `&` prefix:
  #
  # ```ruby
  # class AmpersandExample
  #   include Flexibility
  #
  #   define(:run) do |&blk|
  #     (1..4).each(&blk)
  #   end
  # end
  # ```
  #
  #     irb> AmpersandExample.new.run { |i| puts i }
  #     1
  #     2
  #     3
  #     4
  #     => 1..4
  #
  # Note, however, that the `yield` keyword inside the method body won't be able
  # to access the block bound to the method invocation, as `yield` is lexically
  # scoped (like a local variable).
  #
  # ```ruby
  # module YieldExample
  #   def self.create
  #     Class.new do
  #       include Flexibility
  #       define( :run ) do |&blk|
  #         blk.call :using_block
  #         yield :using_yield
  #       end
  #     end
  #   end
  # end
  # ```
  #
  #     irb> klass = YieldExample.create { |x| puts "class creation block got #{x}" }
  #     irb> instance = klass.new
  #     irb> instance.run { |x| puts "method invocation block got #{x}" }
  #     method invocation block got using_block
  #     class creation block got using_yield
  #
  # ----
  #
  # @param method_name [ Symbol ]
  #   the name of the method to create
  # @param expected    [ { Symbol => [ UnboundMethod(val,key,opts,initial,&blk) ] } ]
  #   an ordered `Hash` of keywords for each argument, associated with an
  #   `Array` of `UnboundMethod` callbacks to call on each argument value when
  #   the defined method is run.
  #
  #   In addition to `UnboundMethod`, qnything that responds to `#to_proc` may
  #   be used for a callback, and a single callback can be used in place of an
  #   `Array` of one callback.
  # @yield
  #   The result of running all the callbacks on each parameter for a given
  #   call to the defined method.
  #
  #   If the block bound to `#define` takes `N+1` parameters, then the first `N`
  #   will be bound to the values of the first `N` keywords. The last
  #   parameter given to the block will contain a `Hash` mapping the remaining
  #   keywords to their values.
  #
  # @raise  [ArgumentError]
  #   If the method body takes `N+1` arguments, but fewer than `N` keywords are
  #   given in the `expected` parameter, then {#define} does not define the
  #   method, and instead raises an error.
  #
  # @raise  [NotImplementedError]
  #   If the method body uses a splat (`*`) to capture a variable number of arguments,
  #   {#define} raises an error, as `Flexibility` has not determined how best to
  #   handle that case yet. Sorry. Bother the developer if you want that
  #   changed.
  #
  # @see #default
  # @see #required
  # @see #validate
  # @see #transform
  def define method_name, expected={}, &method_body
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

      opts = {}
      expected_ums.each.with_index do |(key, ums), i|
        # check positional argument for value first, then default to trailing options
        initial = i < given.length ? given[i] : trailing_opts[key]

        # run every callback, threading the results through each
        final = ums.inject(initial) do |val, um|
          Flexibility::run_unbound_method(um, self, val, key, opts, initial, &blk)
        end

        opts[key] = final unless final.nil?
      end

      # copy remaining options
      (trailing_opts.keys - expected_ums.keys).each do |key|
        opts[key] = trailing_opts[key]
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
  # ----
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
