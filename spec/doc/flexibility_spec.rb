require_relative '../../lib/flexibility'

path = File.expand_path( '../../lib/flexibility.rb', File.dirname(__FILE__) ) 

# mask puts for examples
STRIO = StringIO.new
def puts(msg)
  STRIO.puts msg
end

describe "lib/flexibility.rb examples" do

  # find all comment blocks and parse out the code blocks
  comment_blocks = []
  last_spaces = nil
  last_index  = nil
  code_blocks = nil
  last_mode   = nil
  File.read( path ).each_line.with_index do |line, index|
    next unless line =~ /^( *)#( *)(.*)/
    spaces = $1.length
    indent = $2.length
    comment = $3

    unless spaces == last_spaces and index == last_index + 1
      code_blocks = []
      comment_blocks << { description: comment.sub(/\.*$/, '...'), code_blocks: code_blocks }
      last_mode = nil
    end

    last_spaces = spaces
    last_index  = index

    next unless indent >= 5
    line.sub! '#', ' '

    mode = if comment =~ /^irb> /
             :test
           elsif not [ :output, :test ].include? last_mode
             :eval
           elsif comment =~ /^=> /
             :result
           else
             :output
           end

    case mode
    when :eval
      unless last_mode == :eval
        code_blocks.push( lineno: index+1, lines: [] )
      end
      code_blocks.last[:lines] << line + "\n"
    when :test
      code_blocks.push( lineno: index+1, lines: [line.sub('irb>', '    ')], output: [] )
    when :output
      code_blocks.last[:output] << comment + "\n"
    when :result
      code_blocks.last.merge!( result_lineno: index+1, result: line.sub('=>', '  ') )
    end
    last_mode = mode
  end

  # create a spec out of each comment block that contains code, verifying that
  # the irb results and output are as described
  comment_blocks.each do |block|
    next if block[:code_blocks].empty?

    it block[:description] do
      b = eval( "module #{block[:description].gsub(/^\W+|\W+$/,'').gsub(/\W+/,'_').upcase!} ; binding ;  end" )

      block[:code_blocks].each do |code|
        actual_result = eval( code[:lines].join, b, path, code[:lineno] )
        STRIO.rewind
        actual_output = STRIO.read
        STRIO.rewind
        STRIO.truncate 0

        if code[:result]
          expected_result = eval( code[:result], b, path, code[:result_lineno] )
          eval(%!expect( actual_result ).to eq( expected_result )!, binding, path, code[:lineno] )
        end

        if code[:output]
          expected_output = code[:output].join
          eval( %!expect( actual_output ).to eq( expected_output )!, binding, path, code[:lineno] )
        end
      end
    end
  end
end
