# `Flexibility` is a mix-in for ruby classes that allows you to easily
# {Flexibility::ClassInstanceMethods#define ::define} methods
# that can take a mixture of positional and keyword arguments.
#
# For example, suppose we define
#
#     class Banner
#       include Flexibility
#
#       define :show, {
#         message: required,
#         width:   [
#           default { @width },
#           validate { |n| 0 <= n }
#         ],
#         symbol:  default('*')
#       } do |message,width,symbol,unused_opts|
#         width = [ width, message.length + 4 ].max
#         puts "#{symbol * width}"
#         puts "#{symbol} #{message.ljust(width - 4)} #{symbol}"
#         puts "#{symbol * width}"
#       end
#
#       def initialize
#         @width = 40
#       end
#     end
#
# Popping over to IRB, we could use `Banner#show` with keyword arguments,
#
#     irb> banner = Banner.new
#     irb> banner.show( message: "HELLO", width: 10, symbol: '*' )
#     **********
#     * HELLO  *
#     **********
#      => nil
#
# positional arguments
#
#     irb> banner.show( "HELLO WORLD!", 20, '#' )
#     ####################
#     # HELLO WORLD!     #
#     ####################
#      => nil
#
# or a mix
#
#     irb> banner.show( "A-HA", symbol: '-', width: 15 )
#     ---------------
#     - A-HA        -
#     ---------------
#      => nil
#
# The keyword arguments are taken from the last argument, if it is a Hash, while
# the preceeding positional arguments are matched up to the keyword in the same
# position in the argument description.
#
# `Flexibility` also allows the user to run zero or more callbacks on each
# argument, and includes a number of callback generators to specify a
# {Flexibility#default default} value, mark a given argument as
# {Flexibility#required required}, {Flexibility#validate validate} an argument,
# or {Flexibility#transform transform} an argument into a more acceptable form.
#
# Continuing our prior example, this means `Banner#show` only requires one
# argument, which it automatically upper-cases:
#
#     irb> banner.show( "celery?" )
#     ****************************************
#     * CELERY?                              *
#     ****************************************
#
# And it will raise an error if the `message` is missing or not a String, or if
# the `width` argument is negative:
#
#     irb> show_error = lambda { |&blk| begin ; blk[] ; rescue => e ; [ e.class, e.message ] ; end }
#     irb> show_error.() { banner.show }
#     => [ ArgumentError, "Required argument :message not given" ]
#     irb> show_error.() { banner.show 8675309 }
#     => [ ArgumentError, "Invalid value 8675309 given for argument :message" ]
#     irb> show_error.() { banner.show "hello", -9 }
#     => [ ArgumentError, "Invalid value -9 given for argument :width" ]
# 
# Just as `Flexibility#define` allows the method caller to determine whether to
# pass the method arguments positionally, with keywords, or in a mixture of the
# two, it also allows method authors to determine whether the method receives
# arguments in a Hash or positionally:
#
#     class Banner
#       opts_desc = { a: [], b: [], c: [], d: [], e: [] }
#       define :all_positional, opts_desc do |a,b,c,d,e,opts|
#         [ a, b, c, d, e, opts ]
#       end
#       define :all_keyword, opts_desc do |opts|
#         [ opts ]
#       end
#       define :mixture, opts_desc do |a,b,c,opts|
#         [ a, b, c, opts ]
#       end
#     end
#
#     irb> banner.all_positional(1,2,3,4,5)
#     => [ 1, 2, 3, 4, 5, {} ]
#     irb> banner.all_positional(a:1, b:2, c:3, d:4, e:5, f:6)
#     => [ 1, 2, 3, 4, 5, {f:6} ]
#     irb> banner.all_keyword(1,2,3,4,5)
#     => [ { a:1, b:2, c:3, d:4, e:5 } ]
#     irb> banner.all_keyword(a:1, b:2, c:3, d:4, e:5, f:6)
#     => [ { a:1, b:2, c:3, d:4, e:5, f:6 } ]
#     irb> banner.mixture(1,2,3,4,5)
#     => [ 1, 2, 3, { d:4, e:5 } ]
#     irb> banner.mixture(a:1, b:2, c:3, d:4, e:5, f:6)
#     => [ 1, 2, 3, { d:4, e:5, f:6 } ]
#         
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
  #   - an argument containing a constant value
  #   - a block to be bound to the instance and run as needed
  #
  # With the block form, not only do you have access to instance variables,
  # but you also have access to
  #   - the keyword associated with the argument
  #   - the hash of options defined thus far
  #   - the original argument value (if an earlier transformation `nil`'ed it out)
  #   - the block bound to the method invocation
  #
  # For example, given the method `dimensions`:
  #
  #     class Banner
  #       include Flexibility
  #
  #       define :dimensions, {
  #         depth:    default( 1 ),
  #         width:    default { @width },
  #         height:   default { |_key,opts| opts[:width] } ,
  #         duration: default { |&blk| blk[] if blk }
  #       } do |opts|
  #         opts
  #       end
  #
  #       def initialize
  #         @width = 40
  #       end
  #     end
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
    # allows (1) and (2).
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
