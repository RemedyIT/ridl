#--------------------------------------------------------------------
# backend.rb - RIDL backend configurations
#
# Author: Martin Corino
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the RIDL LICENSE which is
# included with this program.
#
# Copyright (c) Remedy IT Expertise BV
#--------------------------------------------------------------------

module IDL
  class Backend

    @@backends = {}

    class ProcessStop < RuntimeError; end

    class Configurator
      attr_reader :backend
      def initialize(be_name, root, title, copyright, version)
        @backend = IDL::Backend.new(be_name, root, title, copyright, version)
        @be_ext_klass = class << @backend; self; end
      end

      def add_backend(be_name)
        @backend.instance_variable_get('@base_backends') << IDL::Backend.load(be_name)
      end

      def on_setup(&block)
        @be_ext_klass.send(:define_method, :_setup_be, &block)
        @be_ext_klass.send(:private, :_setup_be)
      end

      def on_process_input(&block)
        @be_ext_klass.send(:define_method, :_process_input, &block)
        @be_ext_klass.send(:private, :_process_input)
      end
    end

    def self.load(be_name)
      begin
        # load mapping from standard extension dir in Ruby search path
        require "ridlbe/#{be_name}/require"
        IDL.log(1, "> loaded RIDL backend :#{be_name} from #{@@backends[be_name.to_sym].root}")
        # return backend
        return @@backends[be_name.to_sym]
      rescue LoadError => ex
        IDL.error "ERROR: Cannot load RIDL backend [:#{be_name}]"
        IDL.error ex.inspect
        IDL.error(ex.backtrace.join("\n")) if IDL.verbose_level > 0
        exit 1
      end
    end

    def self.configure(be_name, root, title, copyright, version, &block)
      cfg = Configurator.new(be_name, root, title, copyright, version)
      block.call(cfg)
      @@backends[cfg.backend.name] = cfg.backend
    end

    # stop processing of current input and skip to next or exit RIDL
    def self.stop_processing(msg = '')
      raise ProcessStop, msg, caller(1).first
    end

    def initialize(be_name, root, ttl, cpr, ver)
      @name = be_name.to_sym
      @root = root
      @title = ttl
      @copyright = cpr
      @version = (Hash === ver ? ver : { major: ver.to_i, minor: 0, release: 0 })
      @base_backends = []
    end

    attr_reader :name, :root, :title, :copyright

    def version
      "#{@version[:major]}.#{@version[:minor]}.#{@version[:release]}"
    end

    def print_version
      puts "#{title} #{version}"
      puts copyright
      @base_backends.each { |be| puts '---'; be.print_version }
    end

    def lookup_path
      @base_backends.inject([@root]) { |paths, bbe| paths.concat(bbe.lookup_path) }
    end

    def setup_be(optlist, idl_options)
      # initialize base backends in reverse order so each dependent BE can overrule its
      # base settings
      @base_backends.reverse.each { |be| be.setup_be(optlist, idl_options) }
      # initialize this backend
      _setup_be(optlist, idl_options) if self.respond_to?(:_setup_be, true)
    end

    def process_input(parser, params)
      # process input bottom-up
      @base_backends.reverse.each { |be| be.process_input(parser, params) }
      _process_input(parser, params) if self.respond_to?(:_process_input, true)
    end

    @@null_be = nil

    def self.null_be
      @@null_be ||= self.configure('null', '.', 'RIDL Null backend', "Copyright (c) 2013-#{Time.now.year} Remedy IT Expertise BV, The Netherlands", 1) do |becfg|
        becfg.on_setup do |optlist, params|
          # noop
          IDL.log(0, "Setup called for #{becfg.backend.title}")
        end
      end
    end

  end
end
