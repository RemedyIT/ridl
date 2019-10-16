#--------------------------------------------------------------------
# config.rb - IDL language mapping configuration for test backend
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

  module Test
    COPYRIGHT = "Copyright (c) 2007-#{Time.now.year} Remedy IT Expertise BV, The Netherlands".freeze
    TITLE = 'RIDL Test backend'.freeze
    VERSION = {
        :major => 0,
        :minor => 1,
        :release => 0
    }

    ## Configure Test backend
    #
    Backend.configure('test', File.dirname(__FILE__), TITLE, COPYRIGHT, VERSION) do |becfg|

      # setup backend option handling
      #
      becfg.on_setup do |optlist, ridl_params|
        # defaults
        ridl_params[:stubs_only] = false
        ridl_params[:client_stubs] = true
        ridl_params[:expand_includes] = false

        # test specific option switches

        optlist.for_switch '--stubs-only',
                           :description => ["Only generate client stubs, no servant code.",
                                            "Default: off"] do |swcfg|
          swcfg.on_exec do |arg, params|
            params[:client_stubs] = true
            params[:stubs_only] = true
          end
        end
        optlist.for_switch '--no-stubs',
                           :description => ["Do not generate client stubs, only servant code.",
                                            "Default: off"] do |swcfg|
          swcfg.on_exec do |arg, params|
            params[:client_stubs] = false
            params[:stubs_only] = false
          end
        end

        optlist.for_switch '--expand-includes',
                           :description => ["Generate for included IDL inline.",
                                            "Default: off"] do |swcfg|
          swcfg.on_exec do |arg, params|
            params[:expand_includes] = true
          end
        end
      end

      # process input / generate code
      # arguments:
      #   in parser - parser object with full AST from parsed source
      #   in options - initialized option hash
      #
      becfg.on_process_input do |parser, options|
        IDL::Test.process_input(parser,options)
      end # becfg.on_process_input

    end # Backend.configure

    def self.process_input(parser, options, outstream = nil)
      # has a user defined output filename been set
      fixed_output = !options[:output].nil?

      # generate client stubs if requested
      if options[:client_stubs]
        # open output file
        co = outstream || (unless fixed_output
                             GenFile.new(nil, :output_file => $stdout)
                           else
                             GenFile.new(options[:output])
                           end)
        begin
          # process StubWriter
          parser.visit_nodes(::IDL::TestStubWriter.new(co, options))
        rescue => ex
          IDL.log(0, ex)
          IDL.log(0, ex.backtrace.join("\n")) unless ex.is_a? IDL::ParseError
          exit 1
        end
      end

      # determin output file path for servant code and open file
      unless options[:stubs_only]
        so = outstream || (if fixed_output
                             GenFile.new(options[:output])
                           else
                             GenFile.new(nil, :output_file => $stdout)
                           end)
        begin
          # process ServantWriter
          parser.visit_nodes(::IDL::TestServantWriter.new(so, options))
        rescue => ex
          IDL.log(0, ex)
          IDL.log(0, ex.backtrace.join("\n")) unless ex.is_a? IDL::ParseError
          exit 1
        end
      end
    end

    module LeafMixin
      def self.included(klass)
        klass.extend ClassMethods
      end

      module ClassMethods
        def mk_name(nm, is_scoped)
          return nm.dup
        end
      end
    end # module LeafMixin

    IDL::AST::Leaf.class_eval do
      include LeafMixin
    end

    module ScannerMixin

      def chk_identifier(ident)
        ident
      end

    end # module ScannerMixin

    IDL::Scanner.class_eval do
      include ScannerMixin
    end

  end # module Ruby

end # module IDL
