module Flexibility

  module CallbackGenerators
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
      exec = if self == Flexibility 
               proc { |*args,&blk| blk[*args] }
             else
               method(:instance_exec)
             end
              
      opts = {}
      expected.each.with_index do |(key, cb), i|
        # check positional argument for value first, then default to trailing options
        found   = i < given.length ? given[i] : trailing_opts[key]

        case cb
        when Proc   ; opts[key] = exec[found, key, opts, found, &cb]
        when Array  ; opts[key] = cb.inject(found) { |val, p| exec[val, key, opts, found, &p] }
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

      # assume all but the last block argument should capture positional
      # arguments
      keys = expected.keys[ 0 ... method_body.arity - 1]
      define_method(method_name) do |*given| 
        opts = options(given, expected)
        instance_exec(*keys.map { |key| opts.delete key }, opts, &method_body)
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
