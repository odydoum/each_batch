
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "each_batch/version"

Gem::Specification.new do |spec|
  spec.name          = "each_batch"
  spec.version       = EachBatch::VERSION
  spec.authors       = ["Odysseas Doumas"]
  spec.email         = ["odydoum@gmail.com"]

  spec.summary       = 'Improved batch processing in Rails'
  spec.description   = 'Improved batch processing in Rails'
  spec.homepage      = "https://github.com/odydoum/each_batch"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.5.0"


  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "activerecord", ">= 5.2", "< 7.1"
  spec.add_dependency "where_row", "~> 0.1.3"

  spec.add_development_dependency "bundler", "~> 1.17"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "appraisal"
  spec.add_development_dependency "sqlite3"
  spec.add_development_dependency "yard"
  spec.add_development_dependency "gem-release"
end
