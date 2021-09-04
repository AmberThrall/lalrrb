# frozen_string_literal: true

require_relative "lib/lalrrb/version"

Gem::Specification.new do |spec|
  spec.name          = "lalrrb"
  spec.version       = Lalrrb::VERSION
  spec.authors       = ["Amber Thrall"]
  spec.email         = ["amber.rose.thrall@gmail.com"]

  spec.summary       = "LALR(1) parser generator."
  spec.description   = "LALR(1) parser generator."
  spec.homepage      = "https://github.com/AmberThrall/lalrrb"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.4.0"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Dependencies
  spec.add_dependency "ruby-graphviz"

  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'bundler'
end
