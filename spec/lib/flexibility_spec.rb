require_relative '../../lib/flexibility'

describe Flexibility do
  # make `method` available to be called w/o an explicit receiver
  def self.expose target, method
    define_method(method) do |*args,&blk|
      receiver = Symbol === target ? self.send(target) : target
      receiver.send(method, *args, &blk)
    end
  end

  shared_examples_for '::CallbackGenerators#transform' do
    it 'returns the block as a proc' do
      p = proc{}
      transform(&p) == p
    end
  end

  shared_examples_for '::CallbackGenerators#default' do
    describe "when called with a block, returns a proc which" do
      it "returns any non-nil value given it as initial argument without calling the block" do
        ix = 0
        expect(default { ix += 1 }.call(7)).to eq(7)
        expect(default { ix += 1 }.call(false)).to eq(false)
        expect(ix).to eq(0)
      end
      it "calls the block with the other arguments when given nil as initial argument" do
        _ = self
        expect(default { |*args| _.expect(args).to _.eq([]); 5 }.call()).to eq(5)
        expect(default { |*args| _.expect(args).to _.eq([1,2,3]); 5 }.call(nil,1,2,3)).to eq(5)
      end
      it "binds the block to whatever object the return proc is bound to" do
        p = default { self }
        expect( 5.instance_exec(&p) ).to eq(5)
        expect( :foo.instance_exec(nil,1,2,3,&p) ).to eq(:foo)
      end
    end
    describe "when called with a single argument, returns a proc which" do
      it "returns any non-nil value given it as initial argument" do
        expect(default( 5 ).call(7)).to eq(7)
        expect(default( 5 ).call(false)).to eq(false)
      end
      it "returns the argument when given nil as initial argument" do
        expect(default( 5 ).call()).to eq(5)
        expect(default( 5 ).call(nil)).to eq(5)
      end
    end
  end

  shared_examples_for '::CallbackGenerators#required' do
    it 'returns a proc that raises an error if given nil as an initial argument' do
      expect { required[] }.to raise_error(ArgumentError)
      expect { required[nil] }.to raise_error(ArgumentError)
    end
    it 'returns a proc that returns its initial argument if non-nil' do
      expect( required[5] ).to eq(5)
      expect( required[false] ).to eq(false)
    end
  end

  shared_examples_for '::CallbackGenerators#validate' do
    it "returns a proc that returns the initial argument if the block returns truthy on it" do
      expect( validate { true }[ 7 ] ).to eq( 7 )
      expect( validate { true }[ nil ] ).to be( nil )
      expect( validate { true }[ false ] ).to eq( false )
    end
    it "returns a proc that raises an error if the block returns falsy on the initial argument" do
      expect{ validate { false }[ 7 ] }.to raise_error(ArgumentError)
      expect{ validate { false }[ nil ] }.to raise_error(ArgumentError)
      expect{ validate { false }[ false ] }.to raise_error(ArgumentError)
    end
    it "returns a proc that passes all its arguments to the given block" do
      _ = self
      validate { |*args| _.expect(args).to _.eq([]) ; true }[] 
      validate { |*args| _.expect(args).to _.eq([1,2,3,4,5,6]) ; true }[1,2,3,4,5,6] 
    end
  end

  shared_examples_for '::InstanceMethods#options' do
    let (:tag)   { proc { |t| proc { |x| [t, x] } } }
    it 'applies a hash-of-procs to a array-of-values to get a hash-of-results' do
      expect(options(
        ["one", "two", "three"], 
        foo: tag[:first], 
        bar: tag[:second], 
        baz: tag[:third]
      )).to eq( 
        foo: [:first, "one"],
        bar: [:second, "two"],
        baz: [:third, "three"]
      )
    end
    it 'applies the values from a trailing hash in an array-of-values with to their corresponding procs' do
      expect(options(
        [ "one", { bar: "two", baz: "three" } ], 
        foo: tag[:first], 
        bar: tag[:second], 
        baz: tag[:third]
      )).to eq( 
        foo: [:first, "one"],
        bar: [:second, "two"],
        baz: [:third, "three"]
      )
    end
    it "applies the procs from a hash-of-array-of-procs in order to the given value" do
      expect(options(
        ["one", "two", "three"], 
        foo: [ tag[:first1], tag[:first2], tag[:first3] ],
        bar: [ tag[:second] ],
        baz: tag[:third]
      )).to eq( 
        foo: [:first3, [:first2, [:first1, "one"]]],
        bar: [:second, "two"],
        baz: [:third, "three"]
      )
    end
    it "calls the procs that don't have a corresponding value" do
      expect(options(
        ["one"], 
        foo: tag[:first], 
        bar: tag[:second], 
        baz: tag[:third]
      )).to eq( 
        foo: [:first, "one"],
        bar: [:second, nil],
        baz: [:third, nil]
      )
    end
    it "calls each proc with its key" do
      with_key = proc { |v,k| [v,k] }
      expect(options(
        ["one", "two", "three"], 
        foo: with_key, 
        bar: with_key, 
        baz: with_key
      )).to eq( 
        foo: ["one", :foo],
        bar: ["two", :bar],
        baz: ["three", :baz]
      )
    end
    it "calls each proc with the partial results" do
      ix = 0
      _ = self
      callback = proc do |val,_key,partial|
        case ix += 1
        when 1
          _.expect( partial ).to _.eq({})
          1
        when 2,3
          _.expect( partial ).to _.eq(foo: 1)
          2
        when 4
          _.expect( partial ).to _.eq(foo: 1, bar: 2)
          3
        end
      end

      expect(options(
        ["one", "two", "three"], 
        foo: callback, 
        bar: [ callback, callback ],
        baz: callback
      )).to eq(
        foo: 1,
        bar: 2,
        baz: 3
      )
      expect(ix).to eq(4)
    end
    it "calls each proc with the original value" do 
      ix = 0
      _ = self
      callback = proc do |val,_key,_partial,orig|
        case ix += 1
        when 1,2
          _.expect( orig ).to _.eq("one")
          1
        when 3,4
          _.expect( orig ).to _.eq("two")
          2
        when 5
          _.expect( orig ).to _.eq("three")
          3
        end
      end

      expect(options(
        ["one", "two", "three"], 
        foo: [ callback, callback ],
        bar: [ callback, callback ],
        baz: callback
      )).to eq(
        foo: 1,
        bar: 2,
        baz: 3
      )

      expect(ix).to eq(5)
    end
    it "raises an error if the array-of-values is longer than the hash-of-procs" do
      expect do
        options(
          ["one", "two", "three", "four", "five"], 
          foo: tag[:first], 
          bar: tag[:second], 
          baz: tag[:third]
        )
      end.to raise_error( ArgumentError )
    end
    it "calls each proc with the proper value of self" do
      ix = 0
      _ = self
      callback = proc do |val,_key,_partial,orig|
        ix += 1
        _.expect( self ).to _.eq( _.instance )
        true
      end

      expect(options(
        ["one", "two", "three"], 
        foo: [ callback, callback ],
        bar: [ callback, callback ],
        baz: callback
      )).to eq(
        foo: true,
        bar: true,
        baz: true
      )

      expect(ix).to eq(5)
    end
    it "allows you to substitute anything responding to #to_proc for the procs" do
      one   = double('one')
      one_  = double('one_')
      one__ = double('one__')
      two   = double('two')
      two_  = double('two_')

      expect(one).to receive(:first).and_return(one_)
      expect(one_).to receive(:second).and_return(one__)
      expect(two).to receive(:third).and_return(two_)

      expect(options(
        [one, two], 
        foo: [ :first, :second ],
        baz: :third
      )).to eq(
        foo: one__,
        baz: two_
      )
    end
  end

  shared_examples_for '::ClassMethods#define' do
    it "creates a new instance method" do
      define(:foo, {}) {}
      expect( klass.instance_methods ).to include(:foo)
    end
    it "creates a method which passes the given arguments through #options" do
      define(:foo, { a: [] }) {}
      expect( instance ).to receive(:options).with( [1], { a: [] } )
      instance.foo(1)
    end
    it "binds the method body to the receiver" do
      _ = self
      define(:foo, { a: [] }) { _.expect(self).to _.be(_.instance) }
      instance.foo
    end
    it "passes all n arguments to the method body as a hash if the method body takes 1 argument" do
      _ = self
      define(:foo, { a: [], b: [], c: [] }) do |opts|
        _.expect( opts ).to _.eq({ a: 1, b: 2, c: 3 })
      end
      instance.foo(1,2,3)
    end
    it "passes all n arguments to the method body positionally if the method body takes n+1 arguments" do
      _ = self
      define(:foo, { a: [], b: [], c: [] }) do |a,b,c,opts|
        _.expect( a ).to _.eq( 1 )
        _.expect( b ).to _.eq( 2 )
        _.expect( c ).to _.eq( 3 )
        _.expect( opts ).to _.eq({})
      end
      instance.foo(1,2,3)
    end
    it "passes the first k arguments to the method body positionally if the method body takes 1 < k <= n arguments" do
      _ = self
      define(:foo, { a: [], b: [], c: [], d: []  }) do |a,b,opts|
        _.expect( a ).to _.eq( 1 )
        _.expect( b ).to _.eq( 2 )
        _.expect( opts ).to _.eq({ c: 3, d: 4 })
      end
      instance.foo(1,2,3,4)
    end
    it "raises an error if the method body uses a splat" do
      expect { define(:foo, {}) { |*as| } }.to raise_error(NotImplementedError)
    end
    it "raises an error if the method body uses too many arguments" do
      expect { define(:foo, {}) { |a,b,c,opts| } }.to raise_error(ArgumentError)
    end
    it "allows the method body to access a passed block using &" do
      run = false
      define(:foo, {}) { |&blk| blk[5] }
      instance.foo { |n| expect(n).to eq(5) ; run = true}
      expect(run).to be(true)
    end

    # Not possible, according to
    # https://banisterfiend.wordpress.com/2010/11/06/behavior-of-yield-in-define_method/
    it "allows the method body to access a passed block using yield", impossible: true do
      run = false
      define(:foo, {}) { yield 5 }
      instance.foo { |n| expect(n).to eq(5) ; run = true}
      expect(run).to be(true)
    end

  end

  describe "when included" do
    let (:klass) { Class.new { include Flexibility ; def self.inspect ; "#<klass>" ; end } }
    let (:instance) { klass.new.instance_eval { def inspect ; "#<instance>" ; end ; self }  }

    describe '::transform' do
      expose :klass, :transform
      it_behaves_like "::CallbackGenerators#transform"
    end

    describe '#transform' do
      expose :instance, :transform
      it_behaves_like "::CallbackGenerators#transform"
    end

    describe '::default' do
      expose :klass, :default
      it_behaves_like "::CallbackGenerators#default"
    end

    describe '#default' do
      expose :instance, :default
      it_behaves_like "::CallbackGenerators#default"
    end

    describe '::required' do
      expose :klass, :required
      it_behaves_like "::CallbackGenerators#required"
    end

    describe '#required' do
      expose :instance, :required
      it_behaves_like "::CallbackGenerators#required"
    end

    describe '::validate' do
      expose :klass, :validate
      it_behaves_like "::CallbackGenerators#validate"
    end

    describe '#validate' do
      expose :instance, :validate
      it_behaves_like "::CallbackGenerators#validate"
    end

    describe '#options' do
      expose :instance, :options
      it_behaves_like "::InstanceMethods#options"
    end

    describe "::define" do
      expose :klass, :define
      it_behaves_like "::ClassMethods#define"
    end
  end
end
