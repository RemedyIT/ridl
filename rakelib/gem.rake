#--------------------------------------------------------------------
# gem.rake - build file
#
# Author: Martin Corino
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the RIDL LICENSE which is
# included with this program.
#
# Copyright (c) Remedy IT Expertise BV
#--------------------------------------------------------------------
require 'rubygems'
begin
  require 'rubygems/builder'
rescue LoadError
  require 'rubygems/package'
end

require './lib/ridl/version'

module RIDL

  def self.pkg_root
    File.dirname(File.expand_path(File.dirname(__FILE__)))
  end

  def self.define_spec(name, version, &block)
    gemspec = Gem::Specification.new(name,version)
    gemspec.required_rubygems_version = Gem::Requirement.new(">= 0") if gemspec.respond_to? :required_rubygems_version=
    block.call(gemspec)
    gemspec
  end

  def self.build_gem(gemspec)
    if defined?(Gem::Builder)
      gem_file_name = Gem::Builder.new(gemspec).build
    else
      gem_file_name = Gem::Package.build(gemspec)
    end

    pkg_dir = File.join(pkg_root, 'pkg')
    FileUtils.mkdir_p(pkg_dir)

    gem_file_name = File.join(pkg_root, gem_file_name)
    FileUtils.mv(gem_file_name, pkg_dir)
  end
end

desc 'Build RIDL gem'
task :gem do
  gemspec = RIDL.define_spec('ridl', IDL::RIDL_VERSION) do |gem|
    # gem is a Gem::Specification... see https://guides.rubygems.org/specification-reference/ for more options
    gem.summary = %Q{Ruby OMG IDL compiler}
    gem.description = %Q{OMG v3.3 compliant native Ruby IDL compiler frontend with support for pluggable (and stackable) backends.}
    gem.email = 'mcorino@remedy.nl'
    gem.homepage = "https://www.remedy.nl/products/ridl.html"
    gem.authors = ['Martin Corino', 'Johnny Willemsen']
    gem.files = %w{LICENSE README.rdoc}.concat(Dir.glob('lib/**/*').select {|fnm| File.basename(fnm) != 'orb.pidlc'})
    gem.extensions = []
    gem.extra_rdoc_files = %w{LICENSE README.rdoc}
    gem.rdoc_options << '--main' << 'README.rdoc' << '--exclude' << '\.(idl|pidl|diff|ry)'
    gem.executables = []
    gem.license = Gem::Licenses::MIT
  end
  RIDL.build_gem(gemspec)
end
