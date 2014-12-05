COMMENT_RE = {
  'rb' => %r/^( *)(# ?)( *)(.*)/,
  'md' => %r/^()()( *)(.*)/,
}

# mask puts for examples
STROUT = StringIO.new
def puts(msg)
  STROUT.puts msg
end

def extract_examples path
  
  extension = path.sub(/^.*\./,'')

  describe "#{path} examples" do

    # find all comment blocks and parse out the code blocks
    comment_blocks = []
    last_spaces = nil
    last_index  = nil
    code_blocks = nil
    last_mode   = nil
    is_code     = false
    File.read( path ).each_line.with_index do |line, index|
      next unless line =~ COMMENT_RE[extension]
      spaces    = $1.length
      hashmark  = $2
      indent    = $3.length
      comment   = $4

      unless spaces == last_spaces and index - 1 == last_index
        code_blocks = []
        comment_blocks << { description: comment.sub(/\.*$/, '...'), code_blocks: code_blocks }
        last_mode = nil
      end

      last_spaces = spaces
      last_index  = index

      # support ```...``` code blocks
      if comment =~ /^```/
        is_code ^= true
        next
      end

      next unless is_code or indent >= 4
      line.sub! hashmark, hashmark.gsub(/./,' ')

      mode = if comment =~ /^irb> /
               :test
             elsif comment =~ /^=> /
               :result
             elsif comment =~ /^!> \w+: /
               :error
             elsif [ :output, :test ].include? last_mode
               :output
             else
               :eval
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
      when :error
        comment =~ /^!> (\w+): (.*)/
        code_blocks.last.merge!( error_class: $1, error_message: $2.strip )
      end
      last_mode = mode
    end

    # create a spec out of each comment block that contains code, verifying that
    # the irb results and output are as described
    comment_blocks.each do |block|
      next if block[:code_blocks].empty?

      describe block[:description] do

        block[:code_blocks].each_with_index do |code, i|

          next unless code[:result] or code[:output] or code[:error_class]

          desc = "`#{code[:lines].first.strip}`"
          desc.sub!(/`$/, '...`') if code[:lines].length > 1

          it desc do
            b = eval(<<-EVAL)
              module #{block[:description].gsub(/^\W+|\W+$/,'').gsub(/\W+/,'_').upcase!}_RESULT_#{i}
                binding
              end
            EVAL

            actual_result = block[:code_blocks][0 .. i].inject(nil) do |_,x| 
              STROUT.rewind
              STROUT.truncate 0
              begin
                eval( x[:lines].join, b, path, x[:lineno] ) 
              rescue Exception => e
                raise unless x[:error_class]
                eval(<<-CHECK, binding, path, x[:lineno] )
                  expect( e.class.to_s ).to eq(x[:error_class])
                  expect( e.message ).to eq(x[:error_message])
                CHECK
              end
            end

            if code[:result]
              expected_result = eval( code[:result], b, path, code[:result_lineno] )
              eval(%!expect( actual_result ).to eq( expected_result )!, binding, path, code[:lineno] )
            end

            if code[:output]
              STROUT.rewind
              actual_output = STROUT.read
              expected_output = code[:output].join
              eval( %!expect( actual_output ).to eq( expected_output )!, binding, path, code[:lineno] )
            end
          end
        end
      end
    end
  end
end
