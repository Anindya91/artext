# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'artext/version'

Gem::Specification.new do |spec|
  spec.name          = "artext"
  spec.version       = Artext::VERSION
  spec.authors       = ["Anindya Mondal"]
  spec.email         = ["anindyamondal@mazdigital.com"]
  spec.summary       = %q{Extract article from websites.}
  spec.description   = %q{Extract article and other metadata from websites.}
  spec.homepage      = "https://github.com/Anindya91/artext"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.3"


  spec.add_dependency "addressable", "~> 2.5"
  spec.add_dependency "httparty", "~> 0.16"
  spec.add_dependency "fastimage", "~> 2.1"
  spec.add_dependency "mini_magick", "~> 3.7"
  spec.add_dependency "nokogiri", "~> 1.8"
end
