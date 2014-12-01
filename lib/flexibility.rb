module Flexibility

  module CallbackGenerators
    def default(*args,&blk)
      if args.length != (blk ? 0 : 1)
        raise ArgumentError.new("Wrong number of arguments to `default` (expects 0 with a block, or 1 without)", caller)
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
          raise(ArgumentError.new "Required argument #{key.inspect} not given", caller)
        end
        val
      end
    end
    def validate
      lambda do |val, key, opts, orig|
        unless yield(val, key, opts) 
          raise(ArgumentError.new "Invalid value #{orig.inspect} given for argument #{key.inspect}", caller)
        end
        val
      end
    end
    def transform(&blk)
      blk
    end
    # matches for ===
  end

  module InstanceMethods
    # private instance method?
    def options(given, expected)
      # let the caller bundle arguments in a trailing Hash
      trailing_opts = Hash === given.last ? given.pop : {}
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
    def define method_name, expected, &blk
      with_opts = if blk.arity == 0 
                    blk
                  elsif blk.arity < 0 or blk.arity == expected.length
                    lambda { |opts| blk[ *opts.values ] }
                  else
                    keys = expected.keys[ 0 ... blk.arity ]
                    lambda { |opts| blk[ opts.values_at(*keys), opts ] }
                  end

      # TODO: if has_method(options)? to handle Flexibility.define
      define_method(method_name) { |*given| with_opts[options(given, expected)] }
    end
  end

  class <<self
    def append_features(target)
      eigenclass = class<<target;self;end

      copy_methods( target, InstanceMethods, true )
      copy_methods( target, CallbackGenerators, true )
      copy_methods( eigenclass, ClassInstanceMethods, true )
      copy_methods( eigenclass, CallbackGenerators, true )
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

  eigenclass = class<<self;self;end
  copy_methods( eigenclass, InstanceMethods, false )
  copy_methods( eigenclass, ClassInstanceMethods, false )
  copy_methods( eigenclass, CallbackGenerators, false )
end