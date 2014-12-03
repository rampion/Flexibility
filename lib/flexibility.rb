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
#     irb> banner.show( message: "Hello", width: 10, symbol: '*' )
#     **********
#     * Hello  *
#     **********
#      => nil
#
# positional arguments
#
#     irb> banner.show( "Hello World!", 20, '#' )
#     ####################
#     # Hello World!     #
#     ####################
#      => nil
#
# or a mix
#
#     irb> banner.show( "a-ha", symbol: '-', width: 15 ) # mixed keyword and positional arguments
#     ---------------
#     - a-ha        -
#     ---------------
#      => nil
#
# Now
#
#     class Banner
#       def box(*args)
#         width, height, symbol = options(args,
#           width:  [
#             default { @width },
#             validate { |n| n >= 1 }
#           ],
#           height: [
#             default { |_key,opts| opts[:width] } ,
#             validate { |n| n >= 2 }
#           ],
#           symbol: default('*')
#         ).values
#
#         puts "#{symbol * width}"
#         (height-2).times do
#           puts "#{symbol}#{' ' * (width-2)}#{symbol}"
#         end
#         puts "#{symbol * width}"
#       end
#     end
#
# When mixed in, `Flexibility` adds the private class method
# {Flexibility::ClassInstanceMethods#define ::define} to define methods that
# take a mix of positional and keyword arguments and the the private instance
# method {Flexibility::InstanceMethods#options #options} to convert a collection
# of mixed positional and keyword arguments to a Hash.
#
# We can call `Banner#show` and `Banner#box` with positional and keyword
# arguments:
#
#     irb> banner.box( width: 5, height: 5, symbol: '8' ) # all keyword arguments
#     88888
#     8   8
#     8   8
#     8   8
#     88888
#      => nil
#     irb> banner.box( 10, 3, '@' ) # all positional arguments
#     @@@@@@@@@@
#     @        @
#     @@@@@@@@@@
#      => nil
#     irb> banner.box( 3, 7, symbol:'x' ) # mixed keyword and positional arguments
#     xxx
#     x x
#     x x
#     x x
#     x x
#     x x
#     xxx
#      => nil
#
# The keyword arguments are taken from the last argument, if it is a Hash, while
# the preceeding positional arguments are matched up to the keyword in the same
# position in the argument description.
#
# `Flexibility` also allows the user to run zero or more callbacks on each
# argument, and includes a number of callback generators to specify a
# {Flexibility::CallbackGenerators#default default} value, mark a given argument
# as {Flexibility::CallbackGenerators#required required}, {Flexibility::CallbackGenerators#validate validate} an argument,
# or {Flexibility::CallbackGenerators#transform transform} an argument into a
# more acceptable form.
module Flexibility

  module CallbackGenerators
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
    #         depth:  default( 1 ),
    #         width:  default{ @width },
    #         height: default { |_key,opts| opts[:width] } ,
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
    # We can run it with 0, 1, 2, or 3 arguments:
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
    def default(*args,&blk)
      if args.length != (blk ? 0 : 1)
        raise(ArgumentError, "Wrong number of arguments to `default` (expects 0 with a block, or 1 without)", caller)
      elsif blk
        proc { |val, *args| val.nil? ? instance_exec(*args,&blk) : val }
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
  end

  module InstanceMethods
    # private instance method?
    def options(given, expected)
      # let the caller bundle arguments in a trailing Hash
      trailing_opts = Hash === given.last ? given.pop : {}
      unless expected.length >= given.length
        raise(ArgumentError, "Got #{given.length} arguments, but only know how to handle #{expected.length}", caller)
      end

      opts = {}
      expected.each.with_index do |(key, cbs), i|
        # check positional argument for value first, then default to trailing options
        found = i < given.length ? given[i] : trailing_opts[key]

        # take either a single callback or a collection
        cbs = [ cbs ] unless cbs.respond_to? :inject

        # run every callback, threading the results through each
        opts[key] = cbs.inject(found) do |val, cb|
          unless cb.respond_to? :to_proc
            raise(ArgumentError, "Unrecognized expectation #{cb.inspect} for #{key.inspect}, expecting something that responds to #to_proc", caller)
          else
            instance_exec( val, key, opts, found, &cb )
          end
        end
      end

      opts
    end
  end

  module ClassInstanceMethods
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
      define_method(method_name, &method_body)
      method_impl = instance_method(method_name)

      # assume all but the last block argument should capture positional
      # arguments
      keys = expected.keys[ 0 ... method_impl.arity - 1]

      # interpret user arguments using #options, then pass them to the method
      # body
      define_method(method_name) do |*given, &blk|
        opts = options(given, expected)
        method_impl.bind(self).call(
          *keys.map { |key| opts.delete key }.push( opts ).take( method_impl.arity ), &blk
        )
      end
    end
  end

  class <<self
    def append_features(target)
      eigenclass = class<<target;self;end

      # use #options in method bodies
      copy_methods( target, InstanceMethods, true )
      # use #define in class body
      copy_methods( eigenclass, CallbackGenerators, true )

      # use #transform, #validate, etc with either #options or #define
      copy_methods( target, CallbackGenerators, true )
      copy_methods( eigenclass, ClassInstanceMethods, true )
    end
    private
    def copy_methods(dst, src, as_private)
      dst.class_eval do
        src.instance_methods.each do |name|
          define_method(name, src.instance_method(name))
          private name if as_private
        end
      end
    end
  end
end
