Gem::Specification.new do |s|
  s.name    = "Flexibility"
  s.version = "1.0.0"
  s.date    = "2015-01-01"
  s.summary = "include Flexibility; accept keywords or positional arguments to methods"
  s.description = <<-HERE
    Flexibility is a mix-in for ruby classes that allows you to easily
    define methods that can take a mixture of positional and keyword
    arguments.
  HERE
  s.authors   = ["Noah Luck Easterly"]
  s.email     = "noah.easterly@gmail.com"
  s.homepage  = "https://github.com/rampion/Flexibility"

  s.files     = Dir['lib/**/*.rb']

  s.license   = 'Unlicense'
  s.has_rdoc  = "yard"
  s.extra_rdoc_files = ['README.md']
  File.read('.yardopts').split(/\s+/).each do |opt|
    s.rdoc_options << opt
  end
  s.required_ruby_version = '>= 2.0.0'

  s.add_development_dependency 'rspec', '~> 3'
  s.add_development_dependency 'yard', '~> 0.8'
end
