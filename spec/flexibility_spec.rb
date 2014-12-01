require File.join(  File.dirname( __FILE__ ), '..', 'lib', 'flexibility' )

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
    it "returns a proc that runs the given callback on the inital value"
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
  end

  describe "when included" do
    let (:klass) { Class.new { include Flexibility } }
    let (:instance) { klass.new }

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
      it "calls each proc with the proper value of self" do
        ix = 0
        spec = self
        callback = proc do |val,_key,_partial,orig|
          _self = self
          ix += 1
          spec.instance_eval { expect(_self).to eq(instance) }
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
    end
  end
end
