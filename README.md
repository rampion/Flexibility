`Flexibility` is a mix-in for ruby classes that allows you to easily
{Flexibility#define define} methods that can take a mixture of positional
and keyword arguments.

For example, suppose we define

```ruby
class Banner
  include Flexibility

  define :show, {
    message: [
      required,
      validate { |s| String === s },
      transform { |s| s.upcase }
    ],
    width:   [
      default { @width },
      validate { |n| 0 <= n }
    ],
    symbol:  default('*')
  } do |message,width,symbol,unused_opts|
    width = [ width, message.length + 4 ].max
    puts "#{symbol * width}"
    puts "#{symbol} #{message.ljust(width - 4)} #{symbol}"
    puts "#{symbol * width}"
  end

  def initialize
    @width = 40
  end
end
```

Popping over to IRB, we could use `Banner#show` with keyword arguments,

    irb> banner = Banner.new
    irb> banner.show( message: "HELLO", width: 10, symbol: '*' )
    **********
    * HELLO  *
    **********
     => nil

positional arguments

    irb> banner.show( "HELLO WORLD!", 20, '#' )
    ####################
    # HELLO WORLD!     #
    ####################
     => nil

or a mix

    irb> banner.show( "A-HA", symbol: '-', width: 15 )
    ---------------
    - A-HA        -
    ---------------
     => nil

The keyword arguments are taken from the last argument, if it is a Hash, while
the preceeding positional arguments are matched up to the keyword in the same
position in the argument description.

`Flexibility` also allows the user to run zero or more callbacks on each
argument, and includes a number of callback generators to specify a
{Flexibility#default default} value, mark a given argument as
{Flexibility#required required}, {Flexibility#validate validate} an argument,
or {Flexibility#transform transform} an argument into a more acceptable form.

Continuing our prior example, this means `Banner#show` only requires one
argument, which it automatically upper-cases:

    irb> banner.show( "celery?" )
    ****************************************
    * CELERY?                              *
    ****************************************

And it will raise an error if the `message` is missing or not a String, or if
the `width` argument is negative:

    irb> show_error = lambda { |&blk| begin ; blk[] ; rescue => e ; [ e.class, e.message ] ; end }
    irb> show_error.() { banner.show }
    => [ ArgumentError, "Required argument :message not given" ]
    irb> show_error.() { banner.show 8675309 }
    => [ ArgumentError, "Invalid value 8675309 given for argument :message" ]
    irb> show_error.() { banner.show "hello", -9 }
    => [ ArgumentError, "Invalid value -9 given for argument :width" ]

Just as `Flexibility#define` allows the method caller to determine whether to
pass the method arguments positionally, with keywords, or in a mixture of the
two, it also allows method authors to determine whether the method receives
arguments in a Hash or positionally:

```ruby
class Banner
  opts_desc = { a: [], b: [], c: [], d: [], e: [] }
  define :all_positional, opts_desc do |a,b,c,d,e,opts|
    [ a, b, c, d, e, opts ]
  end
  define :all_keyword, opts_desc do |opts|
    [ opts ]
  end
  define :mixture, opts_desc do |a,b,c,opts|
    [ a, b, c, opts ]
  end
end
```

    irb> banner.all_positional(1,2,3,4,5)
    => [ 1, 2, 3, 4, 5, {} ]
    irb> banner.all_positional(a:1, b:2, c:3, d:4, e:5, f:6)
    => [ 1, 2, 3, 4, 5, {f:6} ]
    irb> banner.all_keyword(1,2,3,4,5)
    => [ { a:1, b:2, c:3, d:4, e:5 } ]
    irb> banner.all_keyword(a:1, b:2, c:3, d:4, e:5, f:6)
    => [ { a:1, b:2, c:3, d:4, e:5, f:6 } ]
    irb> banner.mixture(1,2,3,4,5)
    => [ 1, 2, 3, { d:4, e:5 } ]
    irb> banner.mixture(a:1, b:2, c:3, d:4, e:5, f:6)
    => [ 1, 2, 3, { d:4, e:5, f:6 } ]
        
