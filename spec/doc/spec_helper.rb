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

      next unless indent >= 4
      line.sub! hashmark, hashmark.gsub(/./,' ')

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

      describe block[:description] do

        before = []
        block[:code_blocks].each_with_index do |code, i|
          if code[:result]
            it "result of `#{code[:lines].first.strip}...`" do
              b = eval(<<-EVAL)
                module #{block[:description].gsub(/^\W+|\W+$/,'').gsub(/\W+/,'_').upcase!}_RESULT_#{i}
                  binding
                end
              EVAL
              block[:code_blocks][0 ... i].each { |x| eval( x[:lines].join, b, path, x[:lineno] ) }

              actual_result = eval( code[:lines].join, b, path, code[:lineno] )
              expected_result = eval( code[:result], b, path, code[:result_lineno] )
              eval(%!expect( actual_result ).to eq( expected_result )!, binding, path, code[:lineno] )
            end
          end

          if code[:output]
            it "output of `#{code[:lines].first.strip}...`" do
              b = eval(<<-EVAL)
                module #{block[:description].gsub(/^\W+|\W+$/,'').gsub(/\W+/,'_').upcase!}_OUTPUT_#{i}
                  binding
                end
              EVAL
              block[:code_blocks][0 ... i].each { |x| eval( x[:lines].join, b, path, x[:lineno] ) }
              STROUT.rewind
              STROUT.truncate 0
              eval( code[:lines].join, b, path, code[:lineno] )
              STROUT.rewind

              actual_output = STROUT.read
              expected_output = code[:output].join
              eval( %!expect( actual_output ).to eq( expected_output )!, binding, path, code[:lineno] )
            end
          end

          before << code
        end
      end
    end
  end
end
