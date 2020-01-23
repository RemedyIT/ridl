#--------------------------------------------------------------------
# optparse_ext.rb - Ruby StdLib OptionParser extensions for RIDL
#
# Author: Martin Corino
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the RIDL LICENSE which is
# included with this program.
#
# Copyright (c) Remedy IT Expertise BV
#--------------------------------------------------------------------
require 'optparse'

# Customize OptionParser RequiredArgument switch class to support
# multi character short switches (single '-' prefix) with (optional)
# arguments.
# These must be defined using a format like '-X<text>' or '-X{text}'
# where 'X' is the common start character for a group of short multichar
# switches.
# Switch arguments should be indicated by either appending '=ARG' or
# ' ARG' giving something like '-X<text>=ARG' or '-X<text> ARG' where
# 'ARG' is an arbitrary non-blank text
class OptionParser::Switch::RequiredArgument
  def initialize(pattern = nil, conv = nil,
                 short = nil, long = nil, arg = nil,
                 desc = ([] if short or long), block = nil, &_block)
    super
    if (@long.nil? || @long.empty?) && (@arg =~ /^(<.*>|[\{].*[\}])((=|\s).*)?/)
      @multichar_short = true
      @has_arg = (@arg =~ /^(<.*>|[\{].*[\}])(=|\s).*$/ ? true : false)
    end
  end
  alias :_org_parse :parse
  def parse(arg, argv)
    if @multichar_short && @has_arg
      # unless arg included in rest of switch or next arg is not a switch
      unless (arg && arg =~ /.*=.*/) || (argv.first =~ /^-/)
        # concatenate next arg
        arg ||= ''
        arg += "=#{argv.shift}"
      end
    end
    self._org_parse(arg, argv)
  end
end

module IDL
  class OptionList

    class Option

      class Group

        class ParamSet

          class Configurator
            def initialize(set)
              @set = set
            end

            def on_exec(&block)
              ext_klass = class << @set; self; end
              ext_klass.send(:define_method, :_exec, &block)
              ext_klass.send(:protected, :_exec)
            end

            def with(param, options = {})
              @set.define_params({param => options})
            end

            def without(*params)
              params.each {|p| @set.params.delete(p.to_sym) }
            end
          end

          attr_reader :params
          def initialize(options)
            @description = Array === options[:description] ? options[:description] : (options[:description] || '').split('\n')
            @all_params = options[:all_params] == true
            @params = {}
            parms = options[:params] || options[:param]
            define_params(parms) if parms
          end

          def run(param, options, *handler_args)
            key = to_key(param)
            if @all_params || @params.has_key?(key)
              param = key if String === param && @params.has_key?(key)
              param_arg = @params.has_key?(param) ? @params[param][:option_name] : param
              if self.respond_to?(:_exec, true)
                _exec(param_arg, options, *handler_args)
              elsif @params.has_key?(param)
                if @params[param][:option_type] == :list
                  options[@params[param][:option_name]] ||= []
                  options[@params[param][:option_name]] << (handler_args.size == 1 ? handler_args.shift : handler_args)
                elsif @params[param][:option_type] == :noop
                  # do nothing
                else
                  options[@params[param][:option_name]] = handler_args.empty? ?
                      (@params[param].has_key?(:option_value) ? @params[param][:option_value] : true) :
                      (handler_args.size == 1 ? handler_args.shift : handler_args)
                end
              end
              return true
            end
            return false
          end

          def description
            @params.values.inject(@description) {|list, vopt| list.concat(vopt[:description] || []) }
          end

          def define_params(spec = {})
            case spec
            when String, Hash
              define_param(spec)
            when Array
              spec.each {|p| define_param(p) }
            end
          end

          private

          def to_key(param)
            return param if Symbol === param
            # convert empty strings to single space strings before symbolizing
            String === param ? (param.empty? ? ' ' : param).to_sym : nil
          end

          def define_param(spec)
            case spec
            when String
              key = to_key(spec)
              @params[key] = { :option_name => key }
            when Hash
              spec.each do |k,v|
                @params[to_key(k)] = (if Hash === v
                  {
                    :option_name => to_key(v[:option_name] || k),
                    :option_type => v[:type],
                    :option_value => v.has_key?(:value) ? v[:value] : true,
                    :description => Array === v[:description] ? v[:description] : (v[:description] || '').split('\n')
                  }
                else
                  { :option_name => to_key(v) }
                end)
              end
            end
          end
        end # ParamSet

        class Configurator
          def initialize(grp)
            @group = grp
          end

          def on_prepare(&block)
            ext_klass = class << @group; self; end
            ext_klass.send(:define_method, :_prepare, &block)
            ext_klass.send(:protected, :_prepare)
          end

          def define_param_set(id, options = {}, &block)
            id = id.to_sym
            raise "option parameter set [#{id}] already exists" if @group.sets.has_key?(id)
            @group.sets[id] = ParamSet.new(options)
            block.call(ParamSet::Configurator.new(@group.sets[id])) if block_given?
          end
          alias :for_params :define_param_set

          def modify_param_set(id, options = {}, &block)
            id = id.to_sym
            parms = options[:params] ? options.delete(:params) : options.delete(:param)
            @group.sets[id] ||= ParamSet.new(options)
            @group.sets[id].define_params(parms) if parms
            block.call(ParamSet::Configurator.new(@group.sets[id])) if block_given?
          end
          alias :modify_params :modify_param_set
          alias :with_params :modify_param_set

          def define_param(id, options={}, &block)
            define_param_set("#{id}_set", options) do |pscfg|
              pscfg.with(id)
              pscfg.on_exec(&block)
            end
          end
          alias :for_param :define_param
          alias :with_param :define_param

          def without_param(id)
            @group.sets.delete("#{id}_set")
          end
          alias :without_set :without_param
          alias :without_params :without_param

        end # Configurator

        attr_reader :sets
        def initialize(id, options)
          @test = options[:test] || true
          @description = Array === options[:description] ? options[:description] : (options[:description] || '').split('\n')
          @sets = {}
          if options[:params] && Hash === options[:params]
            @sets[id] = ParamSet.new(:params => options[:params])
          end
        end

        def description
          @sets.values.inject(@description.dup) {|desc, a| desc.concat(a.description) }
        end

        def run(arg, options)
          ext_args = []
          if self.respond_to?(:_prepare, true)
            result = _prepare(arg, options)
            return false unless result && !result.empty?
            arg = result.shift
            ext_args = result
          else
            case @test
            when TrueClass
            when Regexp
              return false unless @test =~ arg
            else
              return false unless @test == arg
            end
          end
          return handle_sets(arg, options, *ext_args)
        end

        private

        def handle_sets(param, options, *ext_args)
          @sets.values.inject(false) {|f, s| s.run(param, options, *ext_args) || f }
        end
      end # Group

      class Configurator
        def initialize(opt)
          @option = opt
        end

        def define_group(id, options = {}, &block)
          id = id.to_sym
          raise "option group [#{id}] already exists" if @option.groups.has_key?(id)
          @option.groups[id] = Group.new(id, options)
          block.call(Group::Configurator.new(@option.groups[id])) if block_given?
        end
        alias :for_group :define_group

        def modify_group(id, options = {}, &block)
          id = id.to_sym
          parms = options[:params] ? options.delete(:params) : options.delete(:param)
          @option.groups[id] ||= Group.new(id, options)
          grpcfg = Group::Configurator.new(@option.groups[id])
          grpcfg.modify_param_set(id, :params => parms) if parms
          block.call(grpcfg) if block_given?
        end
        alias :with_group :modify_group

        def undefine_group(id)
          @option.groups.delete(id.to_sym)
        end

        def define_param_set(id, options = {}, &block)
          modify_group :default, {:test => true} do |grpcfg|
            grpcfg.define_param_set(id, options, &block)
          end
        end
        alias :for_set :define_param_set
        alias :for_params :define_param_set

        def on_exec(options={}, &block)
          modify_group :default, {:test => true} do |grpcfg|
            grpcfg.modify_param_set(:default, options.merge({:all_params => true})) do |pscfg|
              pscfg.on_exec(&block)
            end
          end
        end

        def define_param(id, options={}, &block)
          modify_group :default, {:test => true} do |grpcfg|
            grpcfg.define_param_set("#{id}_set", options) do |pscfg|
              pscfg.with(id)
              pscfg.on_exec(&block)
            end
          end
        end
        alias :for_param :define_param

        def without_param(id)
          if @option.groups.has_key?(:default)
            modify_group :default do |grpcfg|
              grpcfg.without_set("#{id}_set")
            end
          end
        end
        alias :without_set :without_param
        alias :without_params :without_param
      end

      attr_reader :switch
      attr_reader :type
      attr_reader :separator
      attr_reader :groups
      def initialize(switch, options)
        @switch = switch
        @type = options[:type] || TrueClass
        @separator = options[:separator] == true
        @description = Array === options[:description] ? options[:description] : (options[:description] ? options[:description].split('\n') : [''])
        @groups = {}
      end

      def description(indent = "")
        @groups.values.inject(@description.dup) {|desc, h| desc.concat(h.description.collect {|desc| "\r#{indent}  #{desc}"}) }
      end

      def run(arg, options)
        unless @groups.values.inject(false) {|f, h| h.run(arg, options) || f }
          raise ArgumentError, "unknown option [#{arg}] for switch '#{@switch}'"
        end
      end
    end # Option

    def initialize()
      @options = {}
    end

    def define_switch(switch, options = {}, &block)
      switch = switch.to_s
      raise "switch types mismatch" if @options.has_key?(switch) && options[:type] && options[:type] != @options[switch].type
      @options[switch] ||= Option.new(switch, options)
      block.call(Option::Configurator.new(@options[switch])) if block_given?
    end
    alias :for_switch :define_switch
    alias :switch :define_switch

    def undefine_switch(switch)
      switch = switch.to_s
      @options.delete(switch)
    end

    def to_option_parser(optp, option_holder)
      @options.each do |sw, op|
        (arg_list = [sw]) << op.type
        arg_list.concat(op.description(optp.summary_indent))
        optp.on(*arg_list) do |v|
          op.run(v, option_holder.options)
        end
        optp.separator '' if op.separator
      end
    end

  end # OptionList

end # IDL
