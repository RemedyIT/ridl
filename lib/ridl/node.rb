#--------------------------------------------------------------------
# node.rb - IDL nodes
#
# Author: Martin Corino
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the RIDL LICENSE which is
# included with this program.
#
# Copyright (c) Remedy IT Expertise BV
#--------------------------------------------------------------------
module IDL::AST
  REPO_ID_XCHARS = ['.', '-', '_']
  REPO_ID_RE = /^[#{('a'..'z').to_a.join}#{('A'..'Z').to_a.join}#{('0'..'9').to_a.join}\.\-_\/]+$/

  class Annotation
    def initialize(id, fields = {})
      @id = id.to_sym
      # copy field map transforming all keys to symbols and
      # detecting nested annotation objects
      @fields = fields.inject({}) do |m, (k, v)|
          m[k.to_sym] = case v
              when Array
                v.collect { |ve| Hash === ve ? Annotation.new(*ve.to_a.first) : ve }
              when Hash
                Annotation.new(*v.to_a.first)
              else
                v
            end
          m
        end
    end

    attr_reader :id, :fields

    def is_marker?
      @fields.empty?
    end

    def [](fieldid)
      @fields[(fieldid || '').to_sym]
    end

    def each(&block)
      @fields.each(&block)
    end
  end

  class Annotations
    def initialize
      @index = {}
      @stack = []
    end

    def empty?
      @stack.empty?
    end

    def [](annid)
      (@index[annid] || []).collect { |ix| @stack[ix] }
    end

    def <<(ann)
      (@index[ann.id] ||= []) << @stack.size
      @stack << ann
    end

    def each(&block)
      @stack.each(&block)
    end

    def each_for_id(annid, &block)
      self[annid].each(&block)
    end

    def concat(anns)
      anns.each { |_ann| self << _ann } if anns
    end
  end

  class Leaf
    attr_reader :name, :intern, :scopes, :prefix, :annotations
    attr_accessor :enclosure

    def typename
      self.class.name
    end

    def initialize(_name, _enclosure)
      _name ||= ''
      _name = IDL::Scanner::Identifier.new(_name, _name) unless IDL::Scanner::Identifier === _name
      @name = _name
      @lm_name = nil
      @intern = _name.rjust(1).downcase.intern
      @enclosure = _enclosure
      @scopes = if @enclosure then (@enclosure.scopes.dup << self) else [] end
      @prefix = ''
      @repo_id = nil
      @repo_ver = nil
      @annotations = Annotations.new
    end

    def lm_name
      @lm_name ||= @name.checked_name.dup
    end

    def lm_scopes
      @lm_scopes ||= if @enclosure then (@enclosure.lm_scopes.dup << lm_name) else [] end
    end

    def unescaped_name
      @name.unescaped_name
    end

    def scoped_name
      @scoped_name ||= @scopes.collect { |s| s.name }.join("::").freeze
    end

    def scoped_lm_name
      @scoped_lm_name ||= lm_scopes.join("::").freeze
    end

    def marshal_dump
      [@name, lm_name, @intern, @enclosure, @scopes, @prefix, @repo_id, @repo_ver, @annotations]
    end

    def marshal_load(vars)
      @name, @lm_name, @intern, @enclosure, @scopes, @prefix, @repo_id, @repo_ver, @annotations = vars
      @scoped_name = nil
      @scoped_lm_name = nil
      @lm_scopes = nil
    end

    def is_template?
      @enclosure && @enclosure.is_template?
    end

    def instantiate(instantiation_context, _enclosure, _params = {})
      (instantiation_context[self] = self.class.new(self.name, _enclosure, _params)).copy_from(self, instantiation_context)
    end

    def set_repo_id(id)
      if @repo_id
        if id != @repo_id
          raise "#{self.scoped_name} already has a different repository ID assigned: #{@repo_id}"
        end
      end
      id_arr = id.split(':')
      if @repo_ver
        if id_arr.first != 'IDL' or id_arr.last != @repo_ver
          raise "supplied repository ID (#{id}) does not match previously assigned repository version for #{self.scoped_name} = #{@repo_ver}"
        end
      end
      # check validity of IDL format repo IDs
      if id_arr.first == 'IDL'
        id_arr.shift
        id_str = id_arr.shift.to_s
        raise 'ID identifiers should not start or end with \'/\'' if id_str[0, 1] == '/' or id_str[-1, 1] == '/'
        raise "ID identifiers should not start with one of '#{REPO_ID_XCHARS.join("', '")}'" if REPO_ID_XCHARS.include?(id_str[0, 1])
        raise 'Invalid ID! Only a..z, A..Z, 0..9, \'.\', \'-\', \'_\' or \'\/\' allowed for identifiers' unless REPO_ID_RE =~ id_str
      end
      @repo_id = id
    end

    def set_repo_version(ma, mi)
      ver = "#{ma}.#{mi}"
      if @repo_ver
        if ver != @repo_ver
          raise "#{self.scoped_name} already has a repository version assigned: #{@repo_ver}"
        end
      end
      if @repo_id
        l = @repo_id.split(':')
        if l.last != ver
          raise "supplied repository version (#{ver}) does not match previously assigned repository ID for #{self.scoped_name}: #{@repo_id}"
        end
      end
      @repo_ver = ver
    end

    def prefix=(pfx)
      unless pfx.to_s.empty?
        raise 'ID prefix should not start or end with \'/\'' if pfx[0, 1] == '/' or pfx[-1, 1] == '/'
        raise "ID prefix should not start with one of '#{REPO_ID_XCHARS.join("', '")}'" if REPO_ID_XCHARS.include?(pfx[0, 1])
        raise 'Invalid ID prefix! Only a..z, A..Z, 0..9, \'.\', \'-\', \'_\' or \'\/\' allowed' unless REPO_ID_RE =~ pfx
      end
      self.set_prefix(pfx)
    end

    def replace_prefix(pfx)
      self.prefix = pfx
    end

    def repository_id
      if @repo_id.nil?
        @repo_ver = "1.0" unless @repo_ver
        format("IDL:%s%s:%s",
                if @prefix.empty? then "" else @prefix + "/" end,
                self.scopes.collect { |s| s.name }.join("/"),
                @repo_ver)
      else
        @repo_id
      end
    end

    def has_annotations?
      !@annotations.empty?
    end

    def resolve(_name)
      nil
    end

    def is_local?
      false
    end

  protected

    def set_prefix(pfx)
      @prefix = pfx.to_s
    end

    def copy_from(template, _)
      @prefix = template.instance_variable_get(:@prefix)
      @repo_id = template.instance_variable_get(:@repo_id)
      @repo_ver = template.instance_variable_get(:@repo_ver)
      @annotations = template.instance_variable_get(:@annotations)
      self
    end
  end # Leaf

  class Node < Leaf
    def initialize(name, enclosure)
      super
      @introduced = {}
      @children = []
      introduce(self)
    end

    def marshal_dump
      super() << @children << @introduced
    end

    def marshal_load(vars)
      @introduced = vars.pop
      @children = vars.pop
      super(vars)
    end

    def introduce(node)
      n = (@introduced[node.intern] ||= node)
      raise "#{node.name} is already introduced as a #{n.scoped_name} of #{n.typename}." if n != node
    end

    def undo_introduction(node)
      @introduced.delete(node.intern)
    end

    def redefine(node, _params)
      raise "\"#{node.name}\" is already defined."
    end

    def is_definable?(_type)
      self.class::DEFINABLE.any? do |target|
        _type.ancestors.include? target
      end
    end

    def define(_type, _name, params = {})
      unless is_definable?(_type)
        raise "#{_type} is not definable in #{self.typename}."
      end

      node = search_self(_name)
      if node.nil?
        node = _type.new(_name, self, params)
        node.annotations.concat(params[:annotations])
        node.prefix = @prefix
        introduce(node)
        @children << node
      else
        if _type != node.class
          raise "#{_name} is already defined as a type of #{node.typename}"
        end

        node = redefine(node, params)
      end
      node
    end

    def resolve(_name)
      node = search_enclosure(_name)
      @introduced[node.intern] = node unless node.nil?
      node
    end

    def walk_members(&block)
      @children.each(&block)
    end

    def match_members(&block)
      !(@children.find(&block)).nil?
    end

    def select_members(&block)
      @children.select(&block)
    end

    def replace_prefix(pfx)
      super
      walk_members { |m| m.replace_prefix(pfx) }
    end

  protected
    def children
      @children
    end

    def search_self(_name)
      key = _name.downcase.intern
      node = @introduced[key]
      if not node.nil? and node.name != _name
        raise "\"#{_name}\" clashed with \"#{node.name}\"."
      end

      node
    end

    def search_enclosure(_name)
      node = search_self(_name)
      if node.nil? and not @enclosure.nil?
        node = @enclosure.search_enclosure(_name)
      end
      node
    end

    def walk_members_for_copy(&block)
      self.walk_members(&block)
    end

    def copy_from(_template, instantiation_context)
      super
      _template.__send__(:walk_members_for_copy) do |child|
        _child_copy = child.instantiate(instantiation_context, self)
        @children << _child_copy
        # introduce unless already introduced (happens with module chains)
        @introduced[_child_copy.intern] = _child_copy unless @introduced.has_key?(_child_copy.intern)
      end
      self
    end
  end # Node

  # Forward declarations

  class Module < Node; end
  class Include < Module; end
  class TemplateParam < Leaf; end
  class TemplateModule < Module; end
  class TemplateModuleReference < Leaf; end
  class Derivable < Node; end
  class Interface < Derivable; end
  class ComponentBase < Derivable; end
  class Connector < ComponentBase; end
  class Component < ComponentBase; end
  class Porttype < Node; end
  class Port < Leaf; end
  class Home < ComponentBase; end
  class Valuebox < Leaf; end
  class Valuetype < Derivable; end
  class Typedef < Leaf; end
  class Const < Leaf; end
  class Operation < Node; end
  class Attribute < Leaf; end
  class Parameter < Leaf; end
  class StateMember < Leaf; end
  class Initializer < Leaf; end
  class Finder < Initializer; end
  class Struct < Node; end
  class Member < Leaf; end
  class Union < Node; end
  class UnionMember < Member; end
  class Enum < Leaf; end
  class Enumerator < Leaf; end
  class BitMask < Node; end
  class BitValue < Leaf; end
  class BitSet < Node; end
  class BitField < Leaf; end

  class Module < Node
    DEFINABLE = [
      IDL::AST::Module, IDL::AST::Interface, IDL::AST::Valuebox, IDL::AST::Valuetype, IDL::AST::Const, IDL::AST::Struct,
      IDL::AST::Union, IDL::AST::Enum, IDL::AST::Enumerator, IDL::AST::Typedef, IDL::AST::Include,
      IDL::AST::Home, IDL::AST::Porttype, IDL::AST::Component, IDL::AST::Connector, IDL::AST::BitMask, IDL::AST::BitValue,
      IDL::AST::BitSet, IDL::AST::BitField
    ]
    attr_reader :anchor, :next, :template, :template_params

    def initialize(_name, _enclosure, params)
      super(_name, _enclosure)
      @anchor = params[:anchor]
      @prefix = params[:prefix] || @prefix
      @template = params[:template]
      @template_params = (params[:template_params] || []).dup
      @next = nil
    end

    def has_anchor?
      !@anchor.nil?
    end

    def is_templated?
      @template ? true : false
    end

    def template_param(param)
      return nil unless @template

      param = param.to_s if ::Symbol === param
      if ::String === param
        @template.params.each_with_index do |tp, ix|
          return @template_params[ix] if tp.name == param
        end
        nil
      else
        @template_params[param] rescue nil
      end
    end

    def annotations
      (has_anchor? ? self.anchor : self).get_annotations
    end

    def marshal_dump
      super() << @anchor << @next
    end

    def marshal_load(vars)
      @next = vars.pop
      @anchor = vars.pop
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure)
      super(instantiation_context, _enclosure, {})
    end

    def redefine(node, params)
      case node
      when IDL::AST::Include
        if node.enclosure == self
          return node
        else
          _inc = IDL::AST::Include.new(node.name, self, params)
          _inc.annotations.concat(params[:annotations])
          @children << _inc
          return _inc
        end
      when IDL::AST::Module
        # Module reopening
        _anchor = node.has_anchor? ? node.anchor : node
        _anchor.annotations.concat(params.delete(:annotations))
        _last = _anchor.find_last
        _params = params.merge({ anchor: _anchor, prefix: node.prefix })
        _next = IDL::AST::Module.new(node.name, self, _params)
        _last.set_next(_next)
        @children << _next
        return _next
      when IDL::AST::Interface
        node.annotations.concat(params[:annotations])
        # in case of a forward declaration in the same module ignore it since a previous declaration already exists
        if params[:forward]
          return node if node.enclosure == self
          # forward declaration in different scope (other module section in same file or other file)
        elsif node.is_defined?
          # multiple full declarations are illegal
          raise "#{node.typename} \"#{node.name}\" is already defined."
        end
        if (node.is_abstract? != params[:abstract]) || (node.is_local? != params[:local]) || (node.is_pseudo? != params[:pseudo])
          raise "\"attributes are not the same: \"#{node.name}\"."
        end

        _intf = IDL::AST::Interface.new(node.name, self, params)
        _intf.annotations.concat(node.annotations)
        _intf.prefix = node.prefix
        _intf.instance_variable_set(:@repo_ver, node.instance_variable_get(:@repo_ver))
        _intf.instance_variable_set(:@repo_id, node.instance_variable_get(:@repo_id))

        @children << _intf

        # in case of a full declaration undo the preceding forward introduction and
        # replace by full node
        # (no need to introduce forward declaration since there is a preceding introduction)
        unless params[:forward]
          # replace forward node registration
          node.enclosure.undo_introduction(node)
          introduce(_intf)
        end

        return _intf
      when IDL::AST::Valuetype
        node.annotations.concat(params[:annotations])
        return node if params[:forward]
        if node.is_defined?
          raise "#{node.typename} \"#{node.name}\" is already defined."
        end
        if (node.is_abstract? != params[:abstract])
          raise "\"attributes are not the same: \"#{node.name}\"."
        end

        _new_node = node.class.new(node.name, self, params)
        _new_node.annotations.concat(node.annotations)
        _new_node.prefix = node.prefix
        _new_node.instance_variable_set(:@repo_ver, node.instance_variable_get(:@repo_ver))
        _new_node.instance_variable_set(:@repo_id, node.instance_variable_get(:@repo_id))

        @children << _new_node
        # replace forward node registration
        node.enclosure.undo_introduction(node)
        introduce(_new_node)

        return _new_node
      when IDL::AST::Struct, IDL::AST::Union
        node.annotations.concat(params[:annotations])
        return node if params[:forward]
        if node.is_defined?
          raise "#{node.typename} \"#{node.name}\" is already defined."
        end

        _new_node = node.class.new(node.name, self, params)
        _new_node.annotations.concat(node.annotations)
        _new_node.prefix = node.prefix
        _new_node.instance_variable_set(:@repo_ver, node.instance_variable_get(:@repo_ver))
        _new_node.instance_variable_set(:@repo_id, node.instance_variable_get(:@repo_id))

        node.switchtype = params[:switchtype] if node.is_a?(IDL::AST::Union)

        @children << _new_node
        # replace forward node registration
        node.enclosure.undo_introduction(node)
        introduce(_new_node)

        return _new_node
      end
      raise "#{node.name} is already introduced as #{node.typename} #{node.scoped_name}."
    end

    def undo_introduction(node)
      _mod = (@anchor || self)
      while _mod
        _mod._undo_link_introduction(node)
        _mod = _mod.next
      end
    end

    def replace_prefix(pfx)
      self.prefix = pfx # handles validation
      if @anchor.nil?
        self.replace_prefix_i(pfx)
      else
        @anchor.replace_prefix_i(pfx)
      end
    end

  protected

    def set_prefix(pfx)
      if @anchor.nil?
        self.set_prefix_i(pfx)
      else
        @anchor.set_prefix_i(pfx)
      end
    end

    def get_annotations
      @annotations
    end

    def copy_from(_template, instantiation_context)
      super
      if _template.has_anchor?
        # module anchor is first to be copied/instantiated and
        # should be registered in instantiation_context
        cp = IDL::AST::TemplateParam.concrete_param(instantiation_context, _template.anchor)
        # concrete param must be a IDL::Type::NodeType and it's node a Module (should never fail)
        raise "Invalid concrete anchor found" unless cp.is_a?(IDL::Type::NodeType) && cp.node.is_a?(IDL::AST::Module)

        @anchor = cp.node
        # link our self into module chain
        @anchor.find_last.set_next(self)
      end
      @next = nil # to be sure
      self
    end

    def replace_prefix_i(pfx)
      walk_members { |m| m.replace_prefix(pfx) }
      # propagate along chain using fast method
      @next.replace_prefix_i(pfx) unless @next.nil?
    end

    def set_prefix_i(pfx)
      @prefix = pfx
      # propagate along chain
      self.next.set_prefix_i(pfx) unless self.next.nil?
    end

    def search_self(_name)
      (@anchor || self).search_links(_name)
    end

    def search_links(_name)
      _key = _name.downcase.intern
      node = @introduced[_key]
      if not node.nil? and node.name != _name
        raise "\"#{_name}\" clashed with \"#{node.name}\"."
      end

      if node.nil? && @next
        node = @next.search_links(_name)
      end
      node
    end

    def _undo_link_introduction(node)
      @introduced.delete(node.intern)
    end

    def set_next(mod)
      @next = mod
    end

    def find_last
      if @next.nil?
        self
      else
        @next.find_last
      end
    end
  end # Module

  class TemplateParam < Leaf
    attr_reader :idltype, :concrete

    def initialize(_name, _enclosure, params)
      super(_name, _enclosure)
      @idltype = params[:type]
      @concrete = nil
    end

    def marshal_dump
      super() << @idltype
    end

    def marshal_load(vars)
      @idltype = vars.pop
      super(vars)
    end

    def is_template?
      true
    end

    def set_concrete_param(_param)
      @concrete = _param
    end

    def concrete_matches?(idl_type)
      if @concrete
        concrete_type = (@concrete.is_a?(IDL::Type) ? @concrete : @concrete.idltype).resolved_type
        return concrete_type.matches?(idl_type.resolved_type)
      end
      false
    end

    def self.concrete_param(instantiation_context, tpl_elem)
      # is this an element from the template's scope
      if tpl_elem.is_template?
        celem = if tpl_elem.is_a?(IDL::AST::TemplateParam) # an actual template parameter?
          tpl_elem.concrete # get the template parameter's concrete (instantiation argument) value
        else
          # referenced template elements should have been instantiated already and available through context
          ctxelem = instantiation_context[tpl_elem]
          # all items in the context are AST elements but for a concrete parameter value only constants and type
          # elements will be referenced; return accordingly
          ctxelem.is_a?(IDL::AST::Const) ? ctxelem.expression : ctxelem.idltype
        end
        raise "cannot resolve concrete node for template #{tpl_elem.typename} #{tpl_elem.scoped_lm_name}" unless celem

        celem
      else
        tpl_elem.idltype # just return the element's idltype if not from the template scope
      end
    end
  end

  class TemplateModule < Module
    DEFINABLE = [
      IDL::AST::Include, IDL::AST::Module, IDL::AST::Interface, IDL::AST::Valuebox, IDL::AST::Valuetype,
      IDL::AST::Const, IDL::AST::Struct, IDL::AST::Union, IDL::AST::Enum, IDL::AST::Enumerator, IDL::AST::Typedef,
      IDL::AST::Home, IDL::AST::Porttype, IDL::AST::Component, IDL::AST::Connector,
      IDL::AST::TemplateParam, IDL::AST::TemplateModuleReference
    ]
    attr_reader :idltype

    def initialize(_name, _enclosure, _params)
      super(_name, _enclosure, {})
      @idltype = IDL::Type::TemplateModule.new(self)
      @template_params = []
    end

    def define(*args)
      child = super(*args)
      @template_params << child if child.is_a?(IDL::AST::TemplateParam)
      child
    end

    def is_template?
      true
    end

    def params
      @template_params
    end

    def instantiate(_module_instance, instantiation_context = {})
      # process concrete parameters
      @template_params.each_with_index do |_tp, _ix|
        raise "missing template parameter for #{typename} #{scoped_lm_name}: #{_tp.name}" unless _ix < _module_instance.template_params.size

        _cp = _module_instance.template_params[_ix]
        if _cp.is_a?(IDL::Type)
          raise "anonymous type definitions are not allowed!" if _cp.is_anonymous?
          # parameter should be a matching IDL::Type
          unless _tp.idltype.is_a?(IDL::Type::Any) || _tp.idltype.class === _cp.resolved_type
            raise "mismatched instantiation parameter \##{_ix} #{_cp.typename} for #{typename} #{scoped_lm_name}: expected #{_tp.idltype.typename} for #{_tp.name}"
          end

          # verify concrete parameter
          case _tp.idltype
            when IDL::Type::Any # 'typename'
              # no further checks
            when IDL::Type::Interface, # 'interface'
                 IDL::Type::Eventtype, # 'eventtype'
                 IDL::Type::Valuetype, # 'valuetype'
                 IDL::Type::Struct, # 'struct'
                 IDL::Type::Union, # 'union'
                 IDL::Type::Exception, # 'exception'
                 IDL::Type::Enum # 'enum'
                 IDL::Type::BitMask# 'bitmask'
                 IDL::Type::BitSet# 'bitset'
               # no further checks
            when IDL::Type::Sequence # 'sequence' or 'sequence<...>'
              _tptype = _tp.idltype
              unless _tptype.basetype.is_a?(IDL::Type::Void) # 'sequence'
                # check basetype
                unless _tptype.basetype.is_a?(IDL::Type::ScopedName) &&
                       _tptype.basetype.is_node?(IDL::AST::TemplateParam) &&
                       _tptype.basetype.node.concrete_matches?(_cp.resolved_type.basetype)
                  raise "invalid sequence type as instantiation parameter for #{typename} #{scoped_lm_name}: expected #{_tp.idltype.typename} for #{_tp.name}"
                end
              end
          end
        elsif _cp.is_a?(IDL::Expression)
          # template param should be 'const <const_type>'
          unless _tp.idltype.is_a?(IDL::Type::Const)
            raise "unexpected expression as instantiation parameter for #{typename} #{scoped_lm_name}: expected #{_tp.idltype.typename} for #{_tp.name}"
          end

          # match constant type
          _tp.idltype.narrow(_cp.value)
        else
          raise "invalid instantiation parameter for #{typename} #{scoped_lm_name}: #{_cp.class.name}"
        end
        # if we  get here all is well -> store concrete param (either IDL type or expression)
        _tp.set_concrete_param(_cp)
      end
      # instantiate template by copying template module state to module instance
      _module_instance.copy_from(self, instantiation_context)
    end

  protected

    def walk_members_for_copy
      @children.each { |c| yield(c) unless c.is_a?(IDL::AST::TemplateParam) }
    end
  end # TemplateModule

  class TemplateModuleReference < Leaf
    def initialize(_name, _enclosure, _params)
      super(_name, _enclosure)
      unless _params[:tpl_type].is_a?(IDL::Type::ScopedName) && _params[:tpl_type].is_node?(IDL::AST::TemplateModule)
        raise "templated module reference type required for #{typename} #{scoped_lm_name}: got #{_params[:tpl_type].typename}"
      end

      @template = _params[:tpl_type].resolved_type.node
      _params[:tpl_params].each do |p|
        unless (p.is_a?(IDL::Type::ScopedName) || p.is_a?(IDL::Expression::ScopedName)) && p.is_node?(IDL::AST::TemplateParam)
          raise "invalid template module parameter for template module reference #{typename} #{scoped_lm_name}: #{p.typename}"
        end
      end
      @params = _params[:tpl_params].collect { |p| p.resolved_node }
    end

    def marshal_dump
      super() << @template << @params
    end

    def marshal_load(vars)
      @params = vars.pop
      @template = vars.pop
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure)
      inst_params = @params.collect do |tp|
        # concrete objects are either Expression or Type
        tp.concrete
      end
      mod_inst = IDL::AST::Module.new(self.name, _enclosure, { template: @template, template_params: inst_params })
      @template.instantiate(mod_inst, instantiation_context)
      mod_inst
    end

    def resolve(_name)
      @template.resolve(_name)
    end
  end # TemplateModuleReference

  class Include < Module
    attr_reader :filename, :fullpath

    def initialize(_name, _enclosure, params)
      super(_name, _enclosure, params)
      @filename = params[:filename]
      @fullpath = params[:fullpath]
      @defined = params[:defined] || false
      @preprocessed = params[:preprocessed] || false
      # overrule
      @scopes = @enclosure.scopes
      @scoped_name = @scopes.collect { |s| s.name }.join("::")
    end

    def lm_scopes
      @lm_scopes ||= @enclosure.lm_scopes
    end

    def marshal_dump
      super() << @filename << @defined << @preprocessed
    end

    def marshal_load(vars)
      @preprocessed = vars.pop
      @defined = vars.pop
      @filename = vars.pop
      super(vars)
      # overrule
      @scopes = @enclosure.scopes || []
      @scoped_name = @scopes.collect { |s| s.name }.join("::")
    end

    def is_defined?
      @defined
    end

    def is_preprocessed?
      @preprocessed
    end

    def introduce(node)
      @enclosure.introduce(node) unless node == self
    end

    def undo_introduction(node)
      @enclosure.undo_introduction(node) unless node == self
    end

    def resolve(_name)
      @enclosure.resolve(_name)
    end

  protected
    def copy_from(_template, instantiation_context)
      super
      @filename = _template.filename
      @defined = _template.is_defined?
      @preprocessed = _template.is_preprocessed?
      # overrule
      @scopes = @enclosure.scopes
      @scoped_name = @scopes.collect { |s| s.name }.join("::")
      self
    end

    def search_self(_name)
      @enclosure.search_self(_name)
    end
  end # Include

  class Derivable < Node
    alias :search_self_before_derived :search_self
    def search_self(_name)
      node = search_self_before_derived(_name)
      node = search_ancestors(_name) if node.nil?
      node
    end

    def has_ancestor?(n)
      self.has_base?(n) || resolved_bases.any? { |b| b.has_ancestor?(n) }
    end

  protected

    def resolved_bases
      []
    end

    def each_ancestors(visited = [], &block)
      resolved_bases.each do |p|
        next if visited.include? p

        yield(p)
        visited.push p
        p.each_ancestors(visited, &block)
      end
    end

    # search inherited interfaces.
    def search_ancestors(_name)
      results = []
      self.each_ancestors do |interface|
        node = interface.search_self(_name)
        results.push(node) unless node.nil?
      end
      if results.size > 1
        # check if the matched name resulted in multiple different nodes or all the same
        r_one = results.shift
        unless results.all? { |r| r_one == r || (r_one.class == r.class && r_one.scoped_name == r.scoped_name) }
          s = results.inject([r_one]) { |l, r| l << r unless l.include?(r)
 l }.collect { |n| n.scoped_name }.join(", ")
          raise "\"#{_name}\" is ambiguous. " + s
        end
      end
      results.first
    end

    # recursively collect operations from bases
    def base_operations(traversed)
      traversed.push self
      ops = []
      resolved_bases.each do |base|
        base = base.idltype.resolved_type.node if base.is_a?(IDL::AST::Typedef)
        ops.concat(base.operations(true, traversed)) unless traversed.include?(base)
      end
      ops
    end

    # recursively collect attributes from bases
    def base_attributes(traversed)
      traversed.push self
      atts = []
      resolved_bases.each do |base|
        base = base.idltype.resolved_type.node if base.is_a?(IDL::AST::Typedef)
        atts.concat(base.attributes(true, traversed)) unless traversed.include?(base)
      end
      atts
    end
  end # Derivable

  class Interface < Derivable
    DEFINABLE = [IDL::AST::Const, IDL::AST::Operation, IDL::AST::Attribute,
                 IDL::AST::Struct, IDL::AST::Union, IDL::AST::Typedef, IDL::AST::Enum, IDL::AST::Enumerator]
    attr_reader :bases, :idltype

    def initialize(_name, _enclosure, params)
      super(_name, _enclosure)
      @bases = []
      @resolved_bases = []
      @defined = !params[:forward]
      @abstract = params[:abstract]
      @pseudo = params[:pseudo]
      @local = params[:local]
      @idltype = IDL::Type::Interface.new(self)
      add_bases(params[:inherits] || [])
    end

    def marshal_dump
      super() << @bases << @resolved_bases << @defined << @abstract << @local << @pseudo << @idltype
    end

    def marshal_load(vars)
      @idltype = vars.pop
      @pseudo = vars.pop
      @local = vars.pop
      @abstract = vars.pop
      @defined = vars.pop
      @resolved_bases = vars.pop
      @bases = vars.pop
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure)
      _params = {
        forward: self.is_forward?,
        abstract: self.is_abstract?,
        pseudo: self.is_pseudo?,
        local: self.is_local?,
        inherits: self.concrete_bases(instantiation_context)
      }
      # instantiate concrete interface def and validate
      # concrete bases
      super(instantiation_context, _enclosure, _params)
    end

    def is_abstract?
      @abstract
    end

    def is_local?
      @local
    end

    def is_pseudo?
      @pseudo
    end

    def is_defined?
      @defined
    end

    def is_forward?
      not @defined
    end

    def add_bases(inherits_)
      inherits_.each do |tc|
        unless tc.is_a?(IDL::Type::ScopedName) && tc.is_node?(IDL::AST::TemplateParam)
          unless (tc.is_a?(IDL::Type::NodeType) && tc.is_node?(IDL::AST::Interface))
            raise "invalid inheritance identifier for #{typename} #{scoped_lm_name}: #{tc.typename}"
          end

          rtc = tc.resolved_type
          if rtc.node.has_ancestor?(self)
            raise "circular inheritance detected for #{typename} #{scoped_lm_name}: #{tc.node.scoped_lm_name} is descendant"
          end
          unless rtc.node.is_defined?
            raise "#{typename} #{scoped_lm_name} cannot inherit from forward declared #{tc.node.typename} #{tc.node.scoped_lm_name}"
          end
          if rtc.node.is_local? and not self.is_local?
            raise "#{typename} #{scoped_lm_name} cannot inherit from 'local' #{tc.node.typename} #{tc.node.scoped_lm_name}"
          end
          if rtc.node.is_pseudo? and not self.is_pseudo?
            raise "#{typename} #{scoped_lm_name} cannot inherit from 'pseudo' #{tc.node.typename} #{tc.node.scoped_lm_name}"
          end
          if self.is_abstract? and not rtc.node.is_abstract?
            raise "'abstract' #{typename} #{scoped_lm_name} cannot inherit from non-'abstract' #{tc.node.typename} #{tc.node.scoped_lm_name}"
          end
          if self.is_local? and rtc.node.is_abstract?
            raise "'local' #{typename} #{scoped_lm_name} cannot inherit from 'abstract' #{tc.node.typename} #{tc.node.scoped_lm_name}"
          end
          if self.has_base?(rtc.node)
            raise "#{typename} #{scoped_lm_name} cannot inherit from #{tc.node.typename} #{tc.node.scoped_lm_name} multiple times"
          end

          # check if we indirectly derive from this base multiple times (which is ok; no further need to check)
          unless @resolved_bases.any? { |b| b.has_ancestor?(rtc.node) }
            # this is a new base so we need to check for member redefinition/ambiguity
            new_op_att_ = []
            rtc.node.walk_members do |m|
              new_op_att_ << m if m.is_a?(IDL::AST::Operation) || m.is_a?(IDL::AST::Attribute)
            end
            if new_op_att_.any? { |n| n_ = self.search_self(n.name)
 n_.is_a?(IDL::AST::Operation) || n_.is_a?(IDL::AST::Attribute) }
              raise "#{typename} #{scoped_lm_name} cannot inherit from #{tc.node.typename} #{tc.node.scoped_lm_name} because of duplicated operations/attributes"
            end
            # no need to check for duplicate member names; this inheritance is ok
          end
          @resolved_bases << rtc.node
        end
        @bases << tc.node
      end
    end

    def has_base?(_base)
      @resolved_bases.any? { |b| b == _base.idltype.resolved_type.node }
    end

    def ancestors
      @resolved_bases
    end

    def operations(include_bases = false, traversed = nil)
      ops = @children.find_all { |c| c.is_a?(IDL::AST::Operation) }
      ops.concat(base_operations(traversed || [])) if include_bases
      ops
    end

    def attributes(include_bases = false, traversed = nil)
      atts = @children.find_all { |c| c.is_a?(IDL::AST::Attribute) }
      atts.concat(base_attributes(traversed || [])) if include_bases
      atts
    end

    def redefine(node, params)
      if node.enclosure == self
        case node
        when IDL::AST::Struct, IDL::AST::Union
          if node.is_defined?
            raise "#{node.typename} \"#{node.name}\" is already defined."
          end

          node.annotations.concat(params[:annotations])

          _new_node = node.class.new(node.name, self, params)
          _new_node.annotations.concat(node.annotations)
          _new_node.prefix = node.prefix
          _new_node.instance_variable_set(:@repo_ver, node.instance_variable_get(:@repo_ver))
          _new_node.instance_variable_set(:@repo_id, node.instance_variable_get(:@repo_id))

          node.switchtype = params[:switchtype] if node.is_a?(IDL::AST::Union)

          @children << _new_node
          # replace forward node registration
          node.enclosure.undo_introduction(node)
          introduce(_new_node)

          return _new_node
        else
          raise "#{node.typename} \"#{node.name}\" is already defined."
        end
      end

      case node
      when IDL::AST::Operation, IDL::AST::Attribute
        raise "#{node.typename} '#{node.scoped_lm_name}' cannot be overridden."
      else
        newnode = node.class.new(node.name, self, params)
        newnode.annotations.concat(params[:annotations])
        introduce(newnode)
        @children << newnode # add overriding child
        return newnode
      end
    end

  protected

    def concrete_bases(instantiation_context)
      # collect all bases and resolve any template param types
      @bases.collect do |base|
        IDL::AST::TemplateParam.concrete_param(instantiation_context, base)
      end
    end

    def resolved_bases
      @resolved_bases
    end
  end # Interface

  class ComponentBase < Derivable
    DEFINABLE = []
    attr_reader :base, :interfaces, :idltype

    def initialize(_name, _enclosure, params)
      super(_name, _enclosure)
      @base = nil
      @resolved_base = nil
      @interfaces = []
      @resolved_interfaces = []
      set_base(params[:base]) if params[:base]
      add_interfaces(params[:supports] || [])
    end

    def marshal_dump
      super() << @base << @resolved_base << @interfaces << @resolved_interfaces << @idltype
    end

    def marshal_load(vars)
      @idltype = vars.pop
      @resolved_interfaces = vars.pop
      @interfaces = vars.pop
      @resolved_base = vars.pop
      @base = vars.pop
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure, _params = {})
      _params.merge!({
        base: @base ? IDL::AST::TemplateParam.concrete_param(instantiation_context, @base) : @base,
        supports: self.concrete_interfaces(instantiation_context)
      })
      # instantiate concrete def and validate
      super(instantiation_context, _enclosure, _params)
    end

    def set_base(parent)
      unless parent.is_a?(IDL::Type::ScopedName) && parent.is_node?(IDL::AST::TemplateParam)
        unless (parent.is_a?(IDL::Type::NodeType) && parent.is_node?(self.class))
          raise "invalid inheritance identifier for #{typename} #{scoped_lm_name}: #{parent.typename}"
        end
        if parent.resolved_type.node.has_base?(self)
          raise "circular inheritance detected for #{typename} #{scoped_lm_name}: #{parent.node.scoped_lm_name} is descendant"
        end

        @resolved_base = parent.resolved_type.node
      end
      @base = parent.node
    end

    def has_base?(n)
      @resolved_base && (@resolved_base == n.idltype.resolved_type.node) # || @resolved_base.has_base?(n))
    end

    def ancestors
      resolved_bases
    end

    def add_interfaces(intfs)
      intfs.each do |tc|
        unless tc.is_a?(IDL::Type::ScopedName) && tc.is_node?(IDL::AST::TemplateParam)
          unless (tc.is_a?(IDL::Type::ScopedName) && tc.is_node?(IDL::AST::Interface))
            raise "invalid inheritance identifier for #{typename} #{scoped_lm_name}: #{tc.typename}"
          end

          rtc = tc.resolved_type
          unless rtc.node.is_defined?
            raise "#{typename} #{scoped_lm_name} cannot support forward declared #{tc.node.typename} #{tc.node.scoped_lm_name}"
          end
          ## TODO : is this legal?
          if rtc.node.is_local?
            raise "#{typename} #{scoped_lm_name} cannot support 'local' #{tc.node.typename} #{tc.node.scoped_lm_name}"
          end
          if rtc.node.is_pseudo?
            raise "#{typename} #{scoped_lm_name} cannot support 'pseudo' #{tc.node.typename} #{tc.node.scoped_lm_name}"
          end
          ## TODO : is this legal?
          # if tc.node.is_abstract?
          #  raise RuntimeError,
          #        "'abstract' #{typename} #{scoped_lm_name} cannot support 'abstract' #{tc.node.typename} #{tc.node.scoped_lm_name}"
          # end
          if self.has_support?(rtc.node)
            raise "#{typename} #{scoped_lm_name} cannot support #{tc.node.typename} #{tc.node.scoped_lm_name} multiple times"
          end

          # check if we indirectly support this base multiple times (which is ok; no further need to check)
          unless @resolved_interfaces.any? { |b| b.has_ancestor?(rtc.node) }
            # this is a new support interface so we need to check for member redefinition/ambiguity
            new_op_att_ = []
            rtc.node.walk_members do |m|
              new_op_att_ << m if m.is_a?(IDL::AST::Operation) || m.is_a?(IDL::AST::Attribute)
            end
            if new_op_att_.any? { |n| n_ = self.search_self(n.name)
 n_.is_a?(IDL::AST::Operation) || n_.is_a?(IDL::AST::Attribute) }
              raise "#{typename} #{scoped_lm_name} cannot support #{tc.node.typename} #{tc.node.scoped_lm_name} because of duplicated operations/attributes"
            end
            # no need to check for duplicate member names; this support is ok
          end
          @resolved_interfaces << rtc.node
        end
        @interfaces << tc.node
      end
    end

    def has_support?(intf)
      @resolved_interfaces.any? { |b| b == intf.idltype.resolved_type.node }
    end

    def supports?(intf)
      self.has_support?(intf) || (@resolved_base && @resolved_base.supports?(intf)) || @resolved_interfaces.any? { |base_i| i.has_ancestor?(intf) }
    end

    def redefine(node, params)
      if node.enclosure == self
        case node
        when IDL::AST::Struct, IDL::AST::Union
          if node.is_defined?
            raise "#{node.typename} \"#{node.name}\" is already defined."
          end

          node.annotations.concat(params[:annotations])

          _new_node = node.class.new(node.name, self, params)
          _new_node.annotations.concat(node.annotations)
          _new_node.prefix = node.prefix
          _new_node.instance_variable_set(:@repo_ver, node.instance_variable_get(:@repo_ver))
          _new_node.instance_variable_set(:@repo_id, node.instance_variable_get(:@repo_id))

          node.switchtype = params[:switchtype] if node.is_a?(IDL::AST::Union)

          @children << _new_node
          # replace forward node registration
          node.enclosure.undo_introduction(node)
          introduce(_new_node)

          return _new_node
        else
          raise "#{node.typename} \"#{node.name}\" is already defined."
        end
      end

      case node
      when IDL::AST::Operation, IDL::AST::Attribute
        raise "#{node.typename} '#{node.scoped_lm_name}' cannot be overridden."
      else
        newnode = node.class.new(node.name, self, params)
        newnode.annotations.concat(params[:annotations])
        introduce(newnode)
        @children << newnode # add overriding child
        return newnode
      end
    end

  protected

    def resolved_bases
      (@resolved_base ? [@resolved_base] : []).concat(@resolved_interfaces)
    end

    def concrete_interfaces(instantiation_context)
      # collect all bases and resolve any template param types
      @interfaces.collect do |_intf|
        IDL::AST::TemplateParam.concrete_param(instantiation_context, _intf)
      end
    end
  end # ComponentBase

  class Home < ComponentBase
    DEFINABLE = [IDL::AST::Const, IDL::AST::Operation, IDL::AST::Attribute, IDL::AST::Initializer, IDL::AST::Finder,
                 IDL::AST::Struct, IDL::AST::Union, IDL::AST::Typedef, IDL::AST::Enum, IDL::AST::Enumerator]
    attr_reader :component, :primarykey

    def initialize(_name, _enclosure, params)
      @component = nil
      @resolved_comp = nil
      @primarykey = nil
      @resolved_pk = nil
      @idltype = IDL::Type::Home.new(self)
      super(_name, _enclosure, params)
      set_component_and_key(params[:component], params[:primarykey])
    end

    def marshal_dump
      super() << @component << @resolved_comp << @primarykey << @resolved_pk
    end

    def marshal_load(vars)
      @resolved_pk = vars.pop
      @primarykey = vars.pop
      @resolved_comp = vars.pop
      @component = vars.pop
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure)
      _params = {
        component: IDL::AST::TemplateParam.concrete_param(instantiation_context, @component),
        primarykey: @primarykey ? IDL::AST::TemplateParam.concrete_param(instantiation_context, @primarykey) : @primarykey
      }
      # instantiate concrete home def and validate
      super(instantiation_context, _enclosure, _params)
    end

    def set_component_and_key(comp, key)
      unless comp&.is_a?(IDL::Type::ScopedName) && comp.is_node?(IDL::AST::TemplateParam)
        unless comp&.is_a?(IDL::Type::ScopedName) && comp.is_node?(IDL::AST::Component)
          raise (comp ?
                  "invalid managed component for #{typename} #{scoped_lm_name}: #{comp.typename}" :
                  "missing managed component specification for #{typename} #{scoped_lm_name}")
        end
        unless comp.resolved_type.node.is_defined?
          raise "#{scoped_lm_name}: #{comp.typename} cannot manage forward declared component #{comp.node.scoped_lm_name}"
        end

        @resolved_comp = comp.resolved_type.node
      end
      unless key&.is_a?(IDL::Type::ScopedName) && key.is_node?(IDL::AST::TemplateParam)
        ## TODO : add check for Components::PrimaryKeyBase base type
        unless key.nil? || (key.is_a?(IDL::Type::ScopedName) && key.is_node?(IDL::AST::Valuetype))
          raise "invalid primary key for #{typename} #{scoped_lm_name}: #{key.typename}"
        end

        @resolved_pk = key.resolved_type.node if key
      end
      @component = comp.node
      @primarykey = key.node if key
    end

    def operations(include_bases = false, traversed = nil)
      ops = @children.find_all { |c| c.is_a?(IDL::AST::Operation) }
      ops.concat(base_operations(traversed || [])) if include_bases
      ops
    end

    def attributes(include_bases = false, traversed = nil)
      atts = @children.find_all { |c| c.is_a?(IDL::AST::Attribute) }
      atts.concat(base_attributes(traversed || [])) if include_bases
      atts
    end
  end # Home

  class Connector < ComponentBase
    DEFINABLE = [IDL::AST::Attribute, IDL::AST::Port]

    def initialize(_name, _enclosure, params)
      @idltype = IDL::Type::Component.new(self)
      super(_name, _enclosure, params)
    end

    def marshal_dump
      super()
    end

    def marshal_load(vars)
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure)
      # instantiate concrete connector def and validate
      super(instantiation_context, _enclosure, {})
    end

    def is_defined?
      true
    end

    def is_forward?
      false
    end

    def add_interfaces(intfs)
      raise "interface support not allowed for #{typename} #{scoped_lm_name}" if intfs && !intfs.empty?
    end

    def set_base(parent)
      unless parent.is_a?(IDL::Type::ScopedName) && parent.is_node?(IDL::AST::TemplateParam)
        unless (parent.is_a?(IDL::Type::NodeType) && parent.is_node?(self.class))
          raise "invalid inheritance identifier for #{typename} #{scoped_lm_name}: #{parent.typename}"
        end

        @resolved_base = parent.resolved_type.node
        if @resolved_base.has_base?(self)
          raise "circular inheritance detected for #{typename} #{scoped_lm_name}: #{parent.node.scoped_lm_name} is descendant"
        end
      end
      @base = parent.node
    end

    def ports(include_bases = false, traversed = nil)
      ports = @children.inject([]) do |lst, c|
        lst.concat(c.ports) if IDL::AST::Port === c
        lst
      end
      ports.concat(base_ports(traversed || [])) if include_bases
      ports
    end

    def attributes(include_bases = false, traversed = nil)
      atts = @children.inject([]) do |lst, c|
        if IDL::AST::Port === c
          lst.concat(c.attributes)
        else
          lst << c
        end
        lst
      end
      atts.concat(base_attributes(traversed || [])) if include_bases
      atts
    end

  protected

    # recursively collect ports from bases
    def base_ports(traversed)
      traversed.push self
      ports = []
      if (base = @resolved_base)
        base = base.idltype.resolved_type.node if base.is_a?(IDL::AST::Typedef)
        ports = base.ports(true, traversed) unless traversed.include?(base)
      end
      ports
    end
  end # Connector

  class Component < ComponentBase
    DEFINABLE = [IDL::AST::Attribute, IDL::AST::Port]

    def initialize(_name, _enclosure, params)
      @idltype = IDL::Type::Component.new(self)
      super(_name, _enclosure, params)
      @defined = !params[:forward]
    end

    def marshal_dump
      super() << @defined
    end

    def marshal_load(vars)
      @defined = vars.pop
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure)
      # instantiate concrete component def and validate
      super(instantiation_context, _enclosure, { forward: self.is_forward? })
    end

    def is_defined?
      @defined
    end

    def is_forward?
      not @defined
    end

    def set_base(parent)
      unless parent.is_a?(IDL::Type::ScopedName) && parent.is_node?(IDL::AST::TemplateParam)
        unless (parent.is_a?(IDL::Type::NodeType) && parent.is_node?(self.class))
          raise "invalid inheritance identifier for #{typename} #{scoped_lm_name}: #{parent.typename}"
        end

        @resolved_base = parent.resolved_type.node
        unless @resolved_base.is_defined?
          raise "#{typename} #{scoped_lm_name} cannot inherit from forward declared #{parent.node.typename} #{parent.node.scoped_lm_name}"
        end
        if @resolved_base.has_base?(self)
          raise "circular inheritance detected for #{typename} #{scoped_lm_name}: #{parent.node.scoped_lm_name} is descendant"
        end
      end
      @base = parent.node
    end

    def ports(include_bases = false, traversed = nil)
      ports = @children.inject([]) do |lst, c|
        lst.concat(c.ports) if IDL::AST::Port === c
        lst
      end
      ports.concat(base_ports(traversed || [])) if include_bases
      ports
    end

    def operations(include_bases = false, traversed = nil)
      include_bases ? base_operations(traversed || []) : []
    end

    def attributes(include_bases = false, traversed = nil)
      atts = @children.inject([]) do |lst, c|
        if IDL::AST::Port === c
          lst.concat(c.attributes)
        else
          lst << c
        end
        lst
      end
      atts.concat(base_attributes(traversed || [])) if include_bases
      atts
    end

  protected

    # recursively collect ports from bases
    def base_ports(traversed)
      traversed.push self
      ports = []
      if (base = @resolved_base)
        base = base.idltype.resolved_type.node if base.is_a?(IDL::AST::Typedef)
        ports = base.ports(true, traversed) unless traversed.include?(base)
      end
      ports
    end
  end # Component

  class Porttype < Node
    DEFINABLE = [IDL::AST::Attribute, IDL::AST::Port]
    attr_reader :idltype

    def initialize(_name, _enclosure, _params)
      super(_name, _enclosure)
      @idltype = IDL::Type::Porttype.new(self)
    end

    def ports
      @children.select { |c| IDL::AST::Port === c }
    end

    def attributes
      @children.select { |c| IDL::AST::Attribute === c }
    end

    def instantiate(instantiation_context, _enclosure)
      super(instantiation_context, _enclosure, {})
    end
  end # Porttype

  class Port < Leaf
    PORTTYPES = [:facet, :receptacle, :emitter, :publisher, :consumer, :port, :mirrorport]
    PORT_MIRRORS = {facet: :receptacle, receptacle: :facet}
    EXTPORTDEF_ANNOTATION = 'ExtendedPortDef'
    attr_reader :idltype, :porttype

    def initialize(_name, _enclosure, params)
      super(_name, _enclosure)
      @idltype  = params[:type]
      @porttype = params[:porttype]
      raise "unknown porttype for  #{typename} #{scoped_lm_name}: #{@porttype}" unless PORTTYPES.include?(@porttype)

      case @porttype
      when :facet, :receptacle
        unless @idltype.is_a?(IDL::Type::Object) ||
              (@idltype.is_a?(IDL::Type::NodeType) && (@idltype.is_node?(IDL::AST::Interface) || @idltype.is_node?(IDL::AST::TemplateParam)))
          raise "invalid type for #{typename} #{scoped_lm_name}:  #{@idltype.typename}"
        end
      when :port, :mirrorport
        unless @idltype.is_a?(IDL::Type::NodeType) && (@idltype.is_node?(IDL::AST::Porttype) || @idltype.is_node?(IDL::AST::TemplateParam))
          raise "invalid type for #{typename} #{scoped_lm_name}:  #{@idltype.typename}"
        end
      else
        unless @idltype.is_a?(IDL::Type::NodeType) && (@idltype.is_node?(IDL::AST::Eventtype) || @idltype.is_node?(IDL::AST::TemplateParam))
          raise "invalid type for #{typename} #{scoped_lm_name}:  #{@idltype.typename}"
        end
      end
      @multiple = params[:multiple] ? true : false
    end

    def instantiate(instantiation_context, _enclosure)
      _params = {
        type: @idltype.instantiate(instantiation_context),
        porttype: @porttype,
        multiple: @multiple
      }
      super(instantiation_context, _enclosure, _params)
    end

    def multiple?
      @multiple
    end

    def expanded_copy(name_pfx, enc)
      p = IDL::AST::Port.new("#{name_pfx}_#{self.name}", enc, {type: @idltype, porttype: @porttype})
      p.annotations << Annotation.new(EXTPORTDEF_ANNOTATION, { extended_port_name: name_pfx, base_name: self.name, mirror: false })
      p # return expanded copy
    end

    def expanded_mirror_copy(name_pfx, enc)
      p = IDL::AST::Port.new("#{name_pfx}_#{self.name}", enc, {type: @idltype, porttype: PORT_MIRRORS[@porttype]})
      p.annotations << Annotation.new(EXTPORTDEF_ANNOTATION, { extended_port_name: name_pfx, base_name: self.name, mirror: true })
      p # return expanded copy
    end

    def ports
      case @porttype
      when :port
        @idltype.resolved_type.node.ports.collect { |p| p.expanded_copy(self.name, self.enclosure) }
      when :mirrorport
        @idltype.resolved_type.node.ports.collect { |p| p.expanded_mirror_copy(self.name, self.enclosure) }
      else
        [self]
      end
    end

    def attributes
      case @porttype
      when :port, :mirrorport
        @idltype.resolved_type.node.attributes.collect { |att|
          exp_a = att.expanded_copy(self.name, self.enclosure)
          exp_a.annotations << Annotation.new(EXTPORTDEF_ANNOTATION, { extended_port_name: self.name, base_name: att.name, mirror: (@porttype == :mirrorport) })
          exp_a # return expanded copy
        }
      else
        []
      end
    end
  end # Port

  class Valuebox < Leaf
    attr_reader :idltype, :boxed_type

    def initialize(_name, _enclosure, params)
      super(_name, _enclosure)
      @idltype = IDL::Type::Valuebox.new(self)
      @boxed_type = params[:type]
      unless @boxed_type.is_a?(IDL::Type::ScopedName) && @boxed_type.is_node?(IDL::AST::TemplateParam)
        if @boxed_type.resolved_type.is_a?(IDL::Type::Valuetype)
          raise "boxing valuetype #{@boxed_type.scoped_lm_name} in Valuebox #{scoped_lm_name} not allowed"
        end
      end
    end

    def is_local?(recurstk = [])
      boxed_type.is_local?(recurstk)
    end

    def marshal_dump
      super() << @idltype << @boxed_type
    end

    def marshal_load(vars)
      @boxed_type = vars.pop
      @idltype = vars.pop
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure)
      _params = {
        type: @boxed_type.instantiate(instantiation_context)
      }
      super(instantiation_context, _enclosure, _params)
    end
  end # Valuebox

  class Valuetype < Derivable
    DEFINABLE = [IDL::AST::Include, IDL::AST::Const, IDL::AST::Operation, IDL::AST::Attribute, IDL::AST::StateMember, IDL::AST::Initializer,
                 IDL::AST::Struct, IDL::AST::Union, IDL::AST::Typedef, IDL::AST::Enum, IDL::AST::Enumerator]
    attr_reader :bases, :interfaces, :idltype

    def initialize(_name, _enclosure, params)
      super(_name, _enclosure)
      @bases = []
      @resolved_bases = []
      @interfaces = []
      @resolved_interfaces = []
      @defined = false
      @recursive = false
      @forward = params[:forward] ? true : false
      @abstract = params[:abstract]
      @idltype = IDL::Type::Valuetype.new(self)
      complete_definition(params)
    end

    def complete_definition(params)
      unless params[:forward]
        @custom = params[:custom] || false
        _inherits = params[:inherits] || {}
        _base = _inherits[:base] || {}
        @truncatable = _base[:truncatable] || false
        if @custom && @truncatable
            raise "'truncatable' attribute *not* allowed for 'custom' #{typename} #{scoped_lm_name}"
        end

        add_bases(_base[:list] || [])
        add_interfaces(_inherits[:supports] || [])
      end
    end

    def marshal_dump
      super() << @bases << @resolved_bases <<
                 @interfaces << @resolved_interfaces <<
                 @defined << @recursive <<
                 @forward << @abstract <<
                 @custom << @truncatable << @idltype
    end

    def marshal_load(vars)
      @idltype = vars.pop
      @truncatable = vars.pop
      @custom = vars.pop
      @abstract = vars.pop
      @forward = vars.pop
      @recursive = vars.pop
      @defined = vars.pop
      @resolved_interfaces = vars.pop
      @interfaces = vars.pop
      @resolved_bases = vars.pop
      @bases = vars.pop
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure)
      _params = {
        forward: self.is_forward?,
        abstract: self.is_abstract?,
        custom: self.is_custom?,
        inherits: {
          base: {
            truncatable: self.is_truncatable?,
            list: self.concrete_bases(instantiation_context)
          },
          supports: self.concrete_interfaces(instantiation_context)
        }
      }
      inst = super(instantiation_context, _enclosure, _params)
      inst.defined = true
      inst
    end

    def is_abstract?
      @abstract
    end

    def is_custom?
      @custom
    end

    def is_truncatable?
      @truncatable
    end

    def is_defined?
      @defined
    end

    def defined=(f)
      @defined = f
    end

    def is_forward?
      @forward
    end

    def is_recursive?
      @recursive
    end

    def recursive=(f)
      @recursive = f
    end

    def is_local?(recurstk = [])
      # not local if forward decl or recursion detected
      return false if is_forward? || recurstk.include?(self)

      recurstk.push self # track root node to detect recursion
      ret = state_members.any? { |m| m.is_local?(recurstk) }
      recurstk.pop
      ret
    end

    def modifier
      if is_abstract?
        :abstract
      elsif is_custom?
        :custom
      elsif is_truncatable?
        :truncatable
      else
        :none
      end
    end

    def has_concrete_base?
      (not @resolved_bases.empty?) and (not @resolved_bases.first.is_abstract?)
    end

    def supports_concrete_interface?
      !(@resolved_interfaces.empty? || @resolved_interfaces.first.is_abstract?)
    end

    def supports_abstract_interface?
      @resolved_interfaces.any? { |intf| intf.is_abstract? }
    end

    def truncatable_ids
      ids = [self.repository_id]
      ids.concat(@resolved_bases.first.truncatable_ids) if self.has_concrete_base? && self.is_truncatable?
      ids
    end

    def add_bases(inherits_)
      inherits_.each do |tc|
        unless tc.is_a?(IDL::Type::ScopedName) && tc.is_node?(IDL::AST::TemplateParam)
          unless (tc.is_a?(IDL::Type::ScopedName) && tc.is_node?(IDL::AST::Valuetype))
            raise "invalid inheritance identifier for #{typename} #{scoped_lm_name}: #{tc.typename}"
          end

          rtc = tc.resolved_type
          if rtc.node.has_ancestor?(self)
            raise "circular inheritance detected for #{typename} #{scoped_lm_name}: #{tc.node.scoped_lm_name} is descendant"
          end
          unless rtc.node.is_defined?
            raise "#{typename} #{scoped_lm_name} cannot inherit from forward declared #{tc.node.typename} #{tc.node.scoped_lm_name}"
          end
          if self.is_abstract? and not rtc.node.is_abstract?
            raise "'abstract' #{typename} #{scoped_lm_name} cannot inherit from non-'abstract' #{tc.node.typename} #{tc.node.scoped_lm_name}"
          end
          if (not self.is_custom?) and rtc.node.is_custom?
            raise "non-'custom' #{typename} #{scoped_lm_name} cannot inherit from 'custom' #{tc.node.typename} #{tc.node.scoped_lm_name}"
          end
          if @resolved_bases.include?(rtc.node)
            raise "#{typename} #{scoped_lm_name} cannot inherit from #{tc.node.typename} #{tc.node.scoped_lm_name} multiple times"
          end

          if (not rtc.node.is_abstract?) and !@bases.empty?
            raise "concrete basevalue #{tc.node.typename} #{tc.node.scoped_lm_name} MUST " +
                  "be first and only non-abstract in inheritance list for #{typename} #{scoped_lm_name}"
          end
          @resolved_bases << rtc.node
        end
        @bases << tc.node
      end
    end

    def add_interfaces(iflist_)
      iflist_.each do |if_|
        unless if_.is_a?(IDL::Type::ScopedName) && if_.is_node?(IDL::AST::TemplateParam)
          unless (if_.is_a?(IDL::Type::ScopedName) && if_.is_node?(IDL::AST::Interface))
            raise "invalid support identifier for #{typename} #{scoped_lm_name}: #{if_.typename}"
          end

          rif_ = if_.resolved_type
          ### @@TODO@@ further validation
          if (not rif_.node.is_abstract?) and !@interfaces.empty?
            raise "concrete interface '#{rif_.node.scoped_lm_name}' inheritance not allowed for #{typename} #{scoped_lm_name}. Valuetypes can only inherit (support) a single concrete interface."
          end
          if (not rif_.node.is_abstract?) && (not is_interface_compatible?(rif_.node))
            raise "#{typename} #{scoped_lm_name} cannot support concrete interface #{rif_.node.scoped_lm_name} because it does not derive from inherited concrete interfaces"
          end

          @resolved_interfaces << rif_.node
        end
        @interfaces << if_.node
      end
    end

    def has_ancestor?(n)
      @resolved_bases.include?(n.idltype.resolved_type.node) || @resolved_bases.any? { |b| b.has_ancestor?(n) }
    end

    def is_interface_compatible?(n)
      if @resolved_interfaces.empty? || @resolved_interfaces.first.is_abstract?
        @resolved_bases.all? { |b| b.is_interface_compatible?(n) }
      else
        n.idltype.resolved_type.node.has_ancestor?(@interfaces.first)
      end
    end

    def define(_type, _name, *args)
      if self.is_abstract? && [IDL::AST::StateMember, IDL::AST::Initializer].include?(_type)
        raise "cannot define statemember #{_name} on abstract #{typename} #{scoped_lm_name}"
      end

      super(_type, _name, *args)
    end

    def walk_members
      @children.each { |c| yield(c) unless c.is_a?(IDL::AST::StateMember) or
                                           c.is_a?(IDL::AST::Operation) or
                                           c.is_a?(IDL::AST::Attribute) or
                                           c.is_a?(IDL::AST::Initializer)
      }
    end

    def state_members
      @children.find_all { |c| c.is_a?(IDL::AST::StateMember) }
    end

    def interface_members
      @children.find_all { |c| c.is_a?(IDL::AST::Operation) or c.is_a?(IDL::AST::Attribute) }
    end

    def initializers
      @children.find_all { |c| c.is_a?(IDL::AST::Initializer) }
    end

    def has_operations_or_attributes?(include_intf = true)
      @children.any? { |c| c.is_a?(IDL::AST::Operation) || c.is_a?(IDL::AST::Attribute) } ||
        @resolved_bases.any? { |b| b.has_operations_or_attributes? } ||
        (include_intf &&
         @resolved_interfaces.any? { |intf| !intf.operations(true).empty? || !intf.attributes(true).empty? })
    end

    def redefine(node, params)
      if node.enclosure == self
        case node
        when IDL::AST::Struct, IDL::AST::Union
          if node.is_defined?
            raise "#{node.typename} \"#{node.name}\" is already defined."
          end

          node.annotations.concat(params[:annotations])

          _new_node = node.class.new(node.name, self, params)
          _new_node.annotations.concat(node.annotations)
          _new_node.prefix = node.prefix
          _new_node.instance_variable_set(:@repo_ver, node.instance_variable_get(:@repo_ver))
          _new_node.instance_variable_set(:@repo_id, node.instance_variable_get(:@repo_id))

          node.switchtype = params[:switchtype] if node.is_a?(IDL::AST::Union)

          @children << _new_node
          # replace forward node registration
          node.enclosure.undo_introduction(node)
          introduce(_new_node)

          return _new_node
        else
          raise "#{node.typename} \"#{node.name}\" is already defined."
        end
      end

      case node
      when IDL::AST::Operation, IDL::AST::Attribute, IDL::AST::StateMember, IDL::AST::Initializer
        raise "#{node.typename} '#{node.scoped_lm_name}' cannot be overridden."
      else
        newnode = node.class.new(node.name, self, params)
        newnode.annotations.concat(params[:annotations])
        introduce(newnode)
        return newnode
      end
    end

  protected

    def walk_members_for_copy
      @children.each { |c| yield(c) }
    end

    def resolved_bases
      @resolved_bases
    end

    def concrete_bases(instantiation_context)
      # collect all bases and resolve any template param types
      @bases.collect do |_base|
        IDL::AST::TemplateParam.concrete_param(instantiation_context, _base)
      end
    end

    def concrete_interfaces(instantiation_context)
      @interfaces.collect do |_intf|
        IDL::AST::TemplateParam.concrete_param(instantiation_context, _intf)
      end
    end
  end # Valuetype

  class Eventtype < Valuetype
    def initialize(_name, _enclosure, params)
      super(_name, _enclosure, params)
      # overrule
      @idltype = IDL::Type::Eventtype.new(self)
    end
  end # Eventtype

  class StateMember < Leaf
    attr_reader :idltype, :visibility

    def initialize(_name, _enclosure, params)
      @is_recursive = false
      @has_incomplete_type = false
      super(_name, _enclosure)
      @idltype = params[:type]
      @visibility = (params[:visibility] == :public ? :public : :private)
      unless @idltype.is_a?(IDL::Type::ScopedName) && @idltype.is_node?(IDL::AST::TemplateParam)
        raise "Anonymous type definitions are not allowed!" if params[:type].is_anonymous?

        ## check for use of incomplete types
        unless @idltype.is_complete?
          ## verify type is used in sequence
          if @idltype.resolved_type.is_a?(IDL::Type::Sequence)
            ## find the (non-sequence) elementtype
            seq_ = @idltype.resolved_type
            mtype = seq_.basetype
            while mtype.resolved_type.is_a? IDL::Type::Sequence
              seq_ = mtype.resolved_type
              mtype = seq_.basetype
            end
            ## is it an incomplete struct, union or valuetype?
            if mtype.is_a? IDL::Type::ScopedName
              case mtype.resolved_type
              when IDL::Type::Struct, IDL::Type::Union, IDL::Type::Valuetype
                unless mtype.node.is_defined?
                  ## check if incomplete struct/union/valuetype is contained within definition of self
                  enc = _enclosure
                  while enc.is_a?(IDL::AST::Struct) || enc.is_a?(IDL::AST::Union) || enc.is_a?(IDL::AST::Valuetype)
                    if enc.scoped_name == mtype.node.scoped_name
                      ## mark enclosure as recursive
                      enc.recursive = true
                      ## mark sequence as recursive type !!! DEPRECATED !!!; leave till R2CORBA updated
                      seq_.recursive = true
                      return
                    end
                    enc = enc.enclosure
                  end
                end
              end
              if mtype.resolved_type.is_a?(IDL::Type::Valuetype)
                # mark member as using an incomplete valuetype; allowed but needs special care
                @has_incomplete_type = true
                return
              end
            end
          elsif @idltype.resolved_type.is_a?(IDL::Type::Valuetype)
            mtype = @idltype.resolved_type
            enc = _enclosure
            while enc.is_a?(IDL::AST::Struct) || enc.is_a?(IDL::AST::Union) || enc.is_a?(IDL::AST::Valuetype)
              if enc.is_a?(IDL::AST::Valuetype) && enc.scoped_name == mtype.node.scoped_name
                ## statemember using recursive valuetype
                ## is enclosed in valuetype itself as part of constructed type
                ## which is allowed and not a problem
                @is_recursive = true
                ## mark enclosure as recursive
                enc.recursive = true
                return
              end
              enc = enc.enclosure
            end
            # mark member as using an incomplete valuetype; allowed but needs special care
            @has_incomplete_type = true
            return
          end
          raise "Incomplete type #{@idltype.typename} not allowed here!"
        end
      end
    end

    def marshal_dump
      super() << @idltype << @visibility << @is_recursive << @has_incomplete_type
    end

    def marshal_load(vars)
      @has_incomplete_type = vars.pop
      @is_recursive = vars.pop
      @visibility = vars.pop
      @idltype = vars.pop
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure)
      _params = {
        type: @idltype.instantiate(instantiation_context),
        visibility: self.visibility
      }
      super(instantiation_context, _enclosure, _params)
    end

    def is_local?(recurstk)
      idltype.is_local?(recurstk)
    end

    def is_public?
      @visibility == :public
    end

    def is_recursive?
      @is_recursive
    end

    def has_incomplete_type?
      @has_incomplete_type
    end
  end # StateMember

  class Initializer < Leaf
    attr_reader :raises, :params

    def initialize(_name, _enclosure, params)
      super(_name, _enclosure)
      @params = (params[:params] || []).collect do |(ptype, pname)|
        IDL::AST::Parameter.new(pname, self, {attribute: :in, type: ptype})
      end
      @raises = []
      self.raises = params[:raises]
    end

    def raises=(exlist)
      exlist.each do |extype|
        unless extype.is_a?(IDL::Type::ScopedName) &&
                  (extype.is_node?(IDL::AST::Exception) || extype.is_node?(IDL::AST::TemplateParam) || extype.resolved_type.is_a?(IDL::Type::Native))
          raise 'Only IDL Exception types allowed in raises declaration.'
        end

        @raises << extype
      end
    end

    def marshal_dump
      super() << @params << @raises
    end

    def marshal_load(vars)
      @raises = vars.pop
      @params = vars.pop
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure)
      _params = {
        raises: self.concrete_raises(instantiation_context)
      }
      _init = super(instantiation_context, _enclosure, _params)
      _init.set_concrete_parameters(instantiation_context, @params)
      _init
    end

  protected

    def concrete_raises(instantiation_context)
      @raises.collect do |ex|
        ex.instantiate(instantiation_context)
      end
    end

    def set_concrete_parameters(instantiation_context, parms)
      @params = parms.collect do |parm|
        IDL::AST::Parameter.new(parm.name, self,
                           { attribute: :in,
                             type: parm.idltype.instantiate(instantiation_context) })
      end
    end
  end # Initializer

  class Finder < Initializer
  end # Finder

  class Const < Leaf
    attr_reader :idltype, :expression, :value

    def initialize(_name, _enclosure, params)
      super(_name, _enclosure)
      @idltype = params[:type]
      @expression = params[:expression]
      @value = nil
      unless @idltype.is_a?(IDL::Type::ScopedName) && @idltype.is_node?(IDL::AST::TemplateParam)
        raise "Anonymous type definitions are not allowed!" if @idltype.is_anonymous?
        raise "Incomplete type #{@idltype.typename} not allowed here!" unless @idltype.is_complete?

        unless @expression.is_a?(IDL::Expression::ScopedName) && @expression.is_node?(IDL::AST::TemplateParam)
          @value = @idltype.narrow(@expression.value)
        end
      end
    end

    def marshal_dump
      super() << @idltype << @expression
    end

    def marshal_load(vars)
      @expression = vars.pop
      @idltype = vars.pop
      super(vars)
      unless @idltype.is_a?(IDL::Type::ScopedName) && @idltype.is_node?(IDL::AST::TemplateParam)
        unless @expression.is_a?(IDL::Expression::ScopedName) && @expression.is_node?(IDL::AST::TemplateParam)
          @value = @idltype.narrow(@expression.value)
        end
      end
    end

    def instantiate(instantiation_context, _enclosure)
      _params = {
        type: @idltype.instantiate(instantiation_context),
        expression: @expression.instantiate(instantiation_context)
      }
      super(instantiation_context, _enclosure, _params)
    end
  end # Const

  class Parameter < Leaf
    IN = 0
    OUT = 1
    INOUT = 2
    ATTRIBUTE_MAP = {
      in: IN,
      out: OUT,
      inout: INOUT
    }
    attr_reader :idltype

    def initialize(_name, _enclosure, params)
      super(_name, _enclosure)
      @idltype = params[:type]
      @attribute = params[:attribute]
      unless ATTRIBUTE_MAP.has_key?(@attribute)
        raise "invalid attribute for parameter: #{params[:attribute]}"
      end

      unless @idltype.is_a?(IDL::Type::ScopedName) && @idltype.is_node?(IDL::AST::TemplateParam)
        raise "Anonymous type definitions are not allowed!" if params[:type].is_anonymous?
        raise "Exception #{@idltype.typename} is not allowed in an argument of an operation!" if @idltype.is_node?(IDL::AST::Exception)

        if @idltype.is_local?
          if _enclosure.enclosure.is_a?(IDL::AST::Interface) && !_enclosure.enclosure.is_local?
            raise "Local type #{@idltype.typename} not allowed for operation on unrestricted interface"
          end
          ## IDL_Valuetype: no problem as valuetype operations are local
        end
        unless @idltype.is_complete?
          if _enclosure.enclosure.is_a?(IDL::AST::Interface)
            raise "Incomplete type #{@idltype.typename} not allowed here!"
          end
          ## IDL_Valuetype: no problem as valuetype operations are local
        end
      end
    end

    def attribute
      ATTRIBUTE_MAP[@attribute]
    end

    def marshal_dump
      super() << @idltype << @attribute
    end

    def marshal_load(vars)
      @attribute = vars.pop
      @idltype = vars.pop
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure)
      _params = {
        type: @idltype.instantiate(instantiation_context),
        attribute: @attribute
      }
      super(instantiation_context, _enclosure, _params)
    end
  end # Parameter

  class Operation < Node
    DEFINABLE = [IDL::AST::Parameter]
    attr_reader :idltype, :oneway, :raises
    attr_accessor :context

    def initialize(_name, _enclosure, params)
      super(_name, _enclosure)
      @idltype = params[:type]
      @oneway = (params[:oneway] == true)
      @in = []
      @out = []
      @raises = []
      @context = nil
      unless @idltype.is_a?(IDL::Type::ScopedName) && @idltype.is_node?(IDL::AST::TemplateParam)
        raise "Anonymous type definitions are not allowed!" if params[:type].is_anonymous?

        if @idltype.is_local?
          if _enclosure.is_a?(IDL::AST::Interface) && !_enclosure.is_local?
            raise "Local type #{@idltype.typename} not allowed for operation on unrestricted interface"
          end
          ## IDL_Valuetype: no problem as valuetype operations are local
        end
        unless @idltype.is_complete?
          if _enclosure.is_a?(IDL::AST::Interface)
            raise "Incomplete type #{@idltype.typename} not allowed here!"
          end
          ## IDL_Valuetype: no problem as valuetype operations are local
        end
      end
    end

    def marshal_dump
      super() << @idltype << @oneway << @in << @out << @raises << @context
    end

    def marshal_load(vars)
      @context = vars.pop
      @raises = vars.pop
      @out = vars.pop
      @in = vars.pop
      @oneway = vars.pop
      @idltype = vars.pop
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure)
      _params = {
        type: @idltype.instantiate(instantiation_context),
        oneway: @oneway
      }
      _op = super(instantiation_context, _enclosure, _params)
      _op.raises = self.concrete_raises(instantiation_context)
      _op.context = @context
      _op
    end

    def raises=(exlist)
      exlist.each do |extype|
        unless extype.is_a?(IDL::Type::ScopedName) &&
                (extype.is_node?(IDL::AST::Exception) || extype.is_node?(IDL::AST::TemplateParam) || extype.resolved_type.is_a?(IDL::Type::Native))
          raise 'Only IDL Exception or Native types allowed in raises declaration.'
        end

        @raises << extype
      end
    end

    def define(*args)
      param = super(*args)
      case param.attribute
      when Parameter::IN
        @in << param
      when Parameter::OUT
        @out << param
      when Parameter::INOUT
        @in << param
        @out << param
      end
      param
    end

    def in_params
      @in
    end

    def out_params
      @out
    end

    def params
      self.children
    end

  protected

    def concrete_raises(instantiation_context)
      @raises.collect do |ex|
        ex.instantiate(instantiation_context)
      end
    end

    def copy_from(_template, instantiation_context)
      super
      self.walk_members do |param|
        case param.attribute
        when Parameter::IN
          @in << param
        when Parameter::OUT
          @out << param
        when Parameter::INOUT
          @in << param
          @out << param
        end
      end
      self
    end
  end # Operation

  class Attribute < Leaf
    attr_reader :idltype, :readonly, :get_raises, :set_raises

    def initialize(_name, _enclosure, params)
      super(_name, _enclosure)
      @idltype = params[:type]
      @get_raises = []
      @set_raises = []
      unless @idltype.is_a?(IDL::Type::ScopedName) && @idltype.is_node?(IDL::AST::TemplateParam)
        raise "Anonymous type definitions are not allowed!" if @idltype.is_anonymous?
        raise "Exception #{@idltype.typename} is not allowed as an attribute!" if @idltype.is_node?(IDL::AST::Exception)

        if @idltype.is_local?
          if _enclosure.is_a?(IDL::AST::Interface) && !_enclosure.is_local?
            raise "Local type #{@idltype.typename} not allowed for operation on unrestricted interface"
          end
          ## IDL_Valuetype: no problem as valuetype operations are local
        end
        unless @idltype.is_complete?
          if _enclosure.is_a?(IDL::AST::Interface)
            raise "Incomplete type #{@idltype.typename} not allowed here!"
          end
          ## IDL_Valuetype: no problem as valuetype operations are local
        end
      end
      @readonly = params[:readonly]
    end

    def marshal_dump
      super() << @idltype << @readonly << @get_raises << @set_raises
    end

    def marshal_load(vars)
      @set_raises = vars.pop
      @get_raises = vars.pop
      @readonly = vars.pop
      @idltype = vars.pop
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure)
      _params = {
        type: @idltype.instantiate(instantiation_context),
        readonly: @readonly
      }
      _att = super(instantiation_context, _enclosure, _params)
      _att.get_raises = self.concrete_get_raises(instantiation_context)
      _att.set_raises = self.concrete_set_raises(instantiation_context)
      _att
    end

    def get_raises=(exlist)
      exlist.each do |extype|
        unless extype.is_a?(IDL::Type::ScopedName) &&
                  (extype.is_node?(IDL::AST::Exception) || extype.is_node?(IDL::AST::TemplateParam) || extype.resolved_type.is_a?(IDL::Type::Native))
          raise 'Only IDL Exception types allowed in raises declaration.' unless extype.resolved_type.node.is_a?(IDL::AST::Exception)
        end
        @get_raises << extype
      end
    end

    def set_raises=(exlist)
      exlist.each do |extype|
        unless extype.is_a?(IDL::Type::ScopedName) &&
                  (extype.is_node?(IDL::AST::Exception) || extype.is_node?(IDL::AST::TemplateParam) || extype.resolved_type.is_a?(IDL::Type::Native))
          raise 'Only IDL Exception types allowed in raises declaration.' unless extype.resolved_type.node.is_a?(IDL::AST::Exception)
        end
        @set_raises << extype
      end
    end

    def expanded_copy(name_pfx, enc)
      att = IDL::AST::Attribute.new("#{name_pfx}_#{self.name}", enc, {type: @idltype, readonly: @readonly})
      att.get_raises = @get_raises unless @get_raises.empty?
      att.set_raises = @set_raises unless @set_raises.empty?
      att
    end

  protected

    def concrete_get_raises(instantiation_context)
      @get_raises.collect do |ex|
        ex.instantiate(instantiation_context)
      end
    end

    def concrete_set_raises(instantiation_context)
      @set_raises.collect do |ex|
        ex.instantiate(instantiation_context)
      end
    end
  end # Attribute

  class Struct < Node
    DEFINABLE = [IDL::AST::Member, IDL::AST::Struct, IDL::AST::Union, IDL::AST::Enum, IDL::AST::Enumerator]
    attr_reader :idltype

    def initialize(_name, _enclosure, params)
      @defined = false
      @recursive = false
      @forward = params[:forward] ? true : false
      super(_name, _enclosure)
      @idltype = IDL::Type::Struct.new(self)
      @base = set_base(params[:inherits])
    end

    def set_base(inherits)
      unless inherits.nil?
        rtc = inherits.resolved_type
        unless rtc.node.is_defined?
         raise "#{typename} #{scoped_lm_name} cannot inherit from forward declared #{rtc.node.typename} #{rtc.node.scoped_lm_name}"
        end
        unless rtc.node.is_a?(IDL::AST::Struct)
          raise "#{typename} #{scoped_lm_name} cannot inherit from non structure #{rtc.node.typename} #{rtc.node.scoped_lm_name}"
        end
        inherits.node
      end
    end

    def base
      @base
    end

    def is_defined?
      @defined
    end

    def defined=(f)
      @defined = f
    end

    def is_forward?
      @forward
    end

    def is_recursive?
      @recursive
    end

    def recursive=(f)
      @recursive = f
    end

    def walk_members
      @children.each { |m| yield(m) unless m.is_a? IDL::AST::Member }
    end

    def members
      @children.find_all { |c| c.is_a? IDL::AST::Member }
    end

    def is_local?(recurstk = [])
      # not local if forward decl or recursion detected
      return false if is_forward? || recurstk.include?(self)

      recurstk.push self # track root node to detect recursion
      ret = members.any? { |m| m.is_local?(recurstk) }
      recurstk.pop
      ret
    end

    def marshal_dump
      super() << @idltype << @defined << @recursive << @forward << @base
    end

    def marshal_load(vars)
      @base = vars.pop
      @forward = vars.pop
      @recursive = vars.pop
      @defined = vars.pop
      @idltype = vars.pop
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure)
      _params = {
        forward: @forward
      }
      _s = super(instantiation_context, _enclosure, _params)
      _s.defined = self.is_defined?
      _s
    end

  protected

    def walk_members_for_copy
      @children.each { |c| yield(c) }
    end
  end # Struct

  class Exception < IDL::AST::Struct
    DEFINABLE = [IDL::AST::Member, IDL::AST::Struct, IDL::AST::Union, IDL::AST::Enum, IDL::AST::Enumerator]
    def initialize(_name, _enclosure, params)
      super(_name, _enclosure, params)
      @idltype = IDL::Type::Exception.new(self)
    end
  end # Exception

  class Member < Leaf
    attr_reader :idltype

    def initialize(_name, _enclosure, params)
      super(_name, _enclosure)
      @idltype = params[:type]
      unless @idltype.is_a?(IDL::Type::ScopedName) && @idltype.is_node?(IDL::AST::TemplateParam)
        raise "Anonymous type definitions are not allowed!" if @idltype.is_anonymous?
        raise "Exception #{@idltype.typename} is not allowed as member!" if @idltype.is_node?(IDL::AST::Exception)

        ## check for use of incomplete types
        unless @idltype.is_complete?
          ## verify type is used in sequence
          if @idltype.resolved_type.is_a? IDL::Type::Sequence
            ## find the (non-sequence) elementtype
            seq_ = @idltype.resolved_type
            mtype = seq_.basetype
            while mtype.resolved_type.is_a? IDL::Type::Sequence
              seq_ = mtype.resolved_type
              mtype = seq_.basetype
            end
            ## is it an incomplete struct, union or valuetype?
            if mtype.is_a? IDL::Type::ScopedName
              case mtype.resolved_type
              when IDL::Type::Struct, IDL::Type::Union, IDL::Type::Valuetype
                unless mtype.node.is_defined?
                  ## check if incomplete struct/union is contained within definition of self
                  enc = _enclosure
                  while enc.is_a?(IDL::AST::Struct) || enc.is_a?(IDL::AST::Union) || enc.is_a?(IDL::AST::Valuetype)
                    if enc.scoped_name == mtype.node.scoped_name
                      ## mark enclosure as recursive
                      enc.recursive = true
                      ## mark sequence as recursive type !!! DEPRECATED !!!; leave till R2CORBA updated
                      seq_.recursive = true
                      return
                    end
                    enc = enc.enclosure
                  end
                end
                return # incomplete types in sequences allowed
              end
            end
          end
          raise "Incomplete type #{@idltype.typename} not allowed here!"
        end
      end
    end

    def is_local?(recurstk)
      idltype.is_local?(recurstk)
    end

    def marshal_dump
      super() << @idltype
    end

    def marshal_load(vars)
      @idltype = vars.pop
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure, _params = {})
      _params.merge!({
        type: @idltype.instantiate(instantiation_context)
      })
      super(instantiation_context, _enclosure, _params)
    end
  end # Member

  class Union < Node
    DEFINABLE = [IDL::AST::UnionMember, IDL::AST::Struct, IDL::AST::Union, IDL::AST::Enum, IDL::AST::Enumerator]
    attr_reader :idltype
    attr_accessor :switchtype

    def initialize(_name, _enclosure, params)
      @defined = false
      @recursive = false
      @forward = params[:forward] ? true : false
      @switchtype = nil
      super(_name, _enclosure)
      @idltype = IDL::Type::Union.new(self)
    end

    def set_switchtype(_switchtype)
      @switchtype = _switchtype
    end

    def is_defined?
      @defined
    end

    def defined=(f)
      @defined = f
    end

    def is_forward?
      @forward
    end

    def is_recursive?
      @recursive
    end

    def recursive=(f)
      @recursive = f
    end

    def walk_members
      @children.each { |m| yield(m) unless m.is_a? IDL::AST::UnionMember }
    end

    def members
      @children.find_all { |c| c.is_a? IDL::AST::UnionMember }
    end

    def is_local?(recurstk = [])
      # not local if forward decl or recursion detected
      return false if is_forward? || recurstk.include?(self)

      recurstk.push self # track root node to detect recursion
      ret = members.any? { |m| m.is_local?(recurstk) }
      recurstk.pop
      ret
    end

    def has_default?
      members.any? { |m| m.labels.include?(:default) }
    end

    def default_label
      swtype = @switchtype.resolved_type
      return nil if IDL::Type::WChar === swtype # No default label detection for wchar
      lbls = members.collect { |m| m.labels.include?(:default) ? [] : m.labels.collect { |l| l.value } }.flatten
      lbls = lbls.sort unless IDL::Type::Boolean === swtype ## work around bug in Ruby 1.9.2
      def_lbl = swtype.min
      while swtype.in_range?(def_lbl)
        return IDL::Expression::Value.new(@switchtype, def_lbl) unless lbls.include?(def_lbl)
        return nil if def_lbl == swtype.max

        def_lbl = swtype.next(def_lbl)
      end
      nil
    end

    def validate_labels
      return if self.is_template?

      labelvals = []
      default_ = false
      members.each { |m|
        ## check union case labels for validity
        m.labels.each { |lbl|
          if lbl == :default
            raise "duplicate case label 'default' for #{typename} #{lm_name}" if default_

            default_ = true
          else
            # correct type
            lv = @switchtype.resolved_type.narrow(lbl.value)
            # doubles
            if labelvals.include? lv
              raise "duplicate case label #{lv} for #{typename} #{lm_name}"
            end

            labelvals << lv
          end
        }
      }
      ## check if default allowed if defined
      if default_
        if @switchtype.resolved_type.range_length == labelvals.size
          raise "'default' case label superfluous for #{typename} #{lm_name}"
        end
      end
    end

    def marshal_dump
      super() << @defined << @recursive << @forward << @idltype << @switchtype
    end

    def marshal_load(vars)
      @switchtype = vars.pop
      @idltype = vars.pop
      @forward = vars.pop
      @recursive = vars.pop
      @defined = vars.pop
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure)
      _params = {
        forward: @forward
      }
      _u = super(instantiation_context, _enclosure, _params)
      _u.set_switchtype(@switchtype.instantiate(instantiation_context))
      _u.validate_labels
      _u.defined = self.is_defined?
      _u
    end

  protected

      def walk_members_for_copy
        @children.each { |c| yield(c) }
      end
  end # Union

  class UnionMember < Member
    attr_reader :labels

    def initialize(_name, _enclosure, params)
      super(_name, _enclosure, params)
      ## if any of the labels is 'default' forget about the others
      if params[:labels].include?(:default)
        @labels = [:default]
      else
        @labels = params[:labels]
      end
    end

    def marshal_dump
      super() << @labels
    end

    def marshal_load(vars)
      @labels = vars.pop
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure)
      _params = {
        labels: @labels.collect { |l| l == :default ? l : l.instantiate(instantiation_context) }
      }
      super(instantiation_context, _enclosure, _params)
    end
  end # UnionMember

  class Enum < Leaf
    attr_reader :idltype, :bitbound, :bitbound_bits

    def initialize(_name, enclosure, params)
      super(_name, enclosure)
      @enums = []
      @idltype = IDL::Type::Enum.new(self)
      @bitbound = IDL::Type::ULong.new
      @bitbound_bits = 32
      annotations.concat(params[:annotations])
    end

    def marshal_dump
      super() << @idltype << @bitbound << @bitbound_bits << @enums
    end

    def marshal_load(vars)
      @enums = vars.pop
      @bitbound = vars.pop
      @bitbound_bits = vars.pop
      @idltype = vars.pop
      super(vars)
    end

    def enumerators
      @enums
    end

    def add_enumerator(n)
      @enums << n
    end

    def determine_bitbound
      bitbound = annotations[:bit_bound].first
      unless bitbound.nil?
        @bitbound_bits = bitbound.fields[:value]
        raise "Missing number of bits for bit_bound annotation for #{name}" if @bitbound_bits.nil?
        raise "Illegal negative bit_bound #{bits} value for #{name}" if @bitbound_bits.negative?
        raise "Illegal zero bit_bound value for #{name}, not #{bits}" if @bitbound_bits.zero?
        raise "Bitbound for #{name} must be <= 32" unless @bitbound_bits <= 32
      end
      @bitbound = IDL::Type::UTinyShort.new if @bitbound_bits.between?(1,8)
      @bitbound = IDL::Type::UShort.new if @bitbound_bits.between?(9,16)
    end

    def instantiate(instantiation_context, _enclosure)
      super(instantiation_context, _enclosure, {})
    end
  end # Enum

  class Enumerator < Leaf
    attr_reader :idltype, :enum, :value

    def initialize(_name, _enclosure, params)
      super(_name, _enclosure)
      @idltype = IDL::Type::ULong.new
      @enum = params[:enum]
      @value = params[:value]
      @enum.add_enumerator(self)
    end

    def marshal_dump
      super() << @idltype << @enum << @value
    end

    def marshal_load(vars)
      @value = vars.pop
      @enum = vars.pop
      @idltype = vars.pop
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure)
      # find already instantiated Enum parent
      _enum = _enclosure.resolve(@enum.name)
      raise "Unable to resolve instantiated Enum scope for enumerator #{@enum.name}::#{name} instantiation" unless _enum

      super(instantiation_context, _enclosure, { enum: _enum, value: @value })
    end
  end # Enumerator

  class BitMask < Node
    DEFINABLE = [IDL::AST::BitValue]
    attr_reader :idltype, :bitbound, :bitbound_bits

    def initialize(name, enclosure, params)
      super(name, enclosure)
      @bitvalues = []
      @idltype = IDL::Type::BitMask.new(self)
      annotations.concat(params[:annotations])
    end

    def marshal_dump
      super() << @idltype << @bitbound << @bitbound_bits << @bitvalues
    end

    def marshal_load(vars)
      @bitvalues = vars.pop
      @bitbound_bits = vars.pop
      @bitbound = vars.pop
      @idltype = vars.pop
      super(vars)
    end

    def bitvalues
      @bitvalues
    end

    def add_bitvalue(n)
      @bitvalues << n
    end

    def determine_bitbound
      bitbound = annotations[:bit_bound].first
      @bitbound_bits = @bitvalues.size
      unless bitbound.nil?
        @bitbound_bits = bitbound.fields[:value]
        raise "Missing number of bits for bit_bound annotation for #{name}" if @bitbound_bits.nil?
        raise "Illegal negative bit_bound #{bits} value for #{name}" if @bitbound_bits.negative?
        raise "Illegal zero bit_bound value for #{name}, not #{bits}" if @bitbound_bits.zero?
        raise "Bitbound for #{name} must be <= 64" unless @bitbound_bits <= 64
      end
      @bitbound = IDL::Type::UTinyShort.new if @bitbound_bits.between?(1,8)
      @bitbound = IDL::Type::UShort.new if @bitbound_bits.between?(9,16)
      @bitbound = IDL::Type::ULong.new if @bitbound_bits.between?(17,32)
      @bitbound = IDL::Type::ULongLong.new if @bitbound_bits.between?(33,64)
    end

    def instantiate(instantiation_context, _enclosure)
      super(instantiation_context, _enclosure, {})
    end
  end # BitMask

  class BitValue < Leaf
    attr_reader :idltype, :bitmask, :position

    def initialize(name, enclosure, params)
      super(name, enclosure)
      @idltype = IDL::Type::ULong.new
      @bitmask = params[:bitmask]
      @position = params[:position]
      annotations.concat(params[:annotations])
      position_annotation = annotations[:position].first
      unless position_annotation.nil?
        @position = position_annotation.fields[:value]
      end
      @bitmask.add_bitvalue(self)
    end

    def marshal_dump
      super() << @idltype << @bitmask << @position
    end

    def marshal_load(vars)
      @position = vars.pop
      @bitmask = vars.pop
      @idltype = vars.pop
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure)
      # find already instantiated BitMask parent
      _bitmask = _enclosure.resolve(@bitmask.name)
      raise "Unable to resolve instantiated BitMask scope for bitvalue #{@bitmask.name}::#{name} instantiation" unless _bitmask

      super(instantiation_context, _enclosure, { bitmask: _bitmask, position: @position })
    end
  end # BitValue

  class BitSet < Node
    DEFINABLE = [IDL::AST::BitField]
    attr_reader :idltype

    def initialize(_name, enclosure, params)
      super(_name, enclosure)
      @bitfields = []
      @bitset_bits = 0
      @idltype = IDL::Type::BitSet.new(self)
      @base = set_base(params[:inherits])
    end

    def set_base(inherits)
      unless inherits.nil?
        rtc = inherits.resolved_type
        unless rtc.node.is_a?(IDL::AST::BitSet)
          raise "#{typename} #{scoped_lm_name} cannot inherit from non bitset #{rtc.node.typename} #{rtc.node.scoped_lm_name}"
        end
        inherits.node
      end
    end

    def base
      @base
    end

    # Override from Node base to handle anonymous bitfields
    def define(_type, _name, params = {})
      unless is_definable?(_type)
        raise "#{_type} is not definable in #{self.typename}."
      end

      # All IDL definables have a name except a bitfield, that has an optional name and can
      # be anonymous
      node = search_self(_name) unless _name.nil?
      if node.nil?
        node = _type.new(_name, self, params)
        node.annotations.concat(params[:annotations])
        node.prefix = @prefix
        introduce(node) unless _name.nil? # If there is no name don't introduce it in our scope
        @children << node
      else
        if _type != node.class
          raise "#{_name} is already defined as a type of #{node.typename}"
        end

        node = redefine(node, params)
      end
      node
    end

    def marshal_dump
      super() << @idltype << @bitset_bits << @bitfields << @bitset
    end

    def marshal_load(vars)
      @bitset = vars.pop
      @bitfields = vars.pop
      @bitset_bits = vars.pop
      @idltype = vars.pop
      super(vars)
    end

    # Total number of bits in this bitset including the optional base
    def bitset_bits
      base.nil? ? @bitset_bits : @bitset_bits + base.bitset_bits
    end

    # Underlying type which is large enough to contain the full bitset
    # including its base
    def underlying_type
      return IDL::Type::UTinyShort.new if bitset_bits.between?(1,8)
      return IDL::Type::UShort.new if bitset_bits.between?(9,16)
      return IDL::Type::ULong.new if bitset_bits.between?(17,32)
      return IDL::Type::ULongLong.new if bitset_bits.between?(33,64)
    end

    def bitfields
      @bitfields
    end

    def add_bitfield(n)
      @bitfields << n
      @bitset_bits += n.bits
    end

    def instantiate(instantiation_context, _enclosure)
      super(instantiation_context, _enclosure, {})
    end
  end # BitSet

  class BitField < Leaf
    attr_reader :idltype, :bitset, :bits

    def initialize(_name, _enclosure, params)
      super(_name, _enclosure)
      @idltype = params[:idltype]
      @bitset = params[:bitset]
      @bits = params[:bits]

      raise "Amount of bits for bitfield #{_name} must <= 64, not #{bits}" if bits > 64

      # When no IDL type has been specified for the bitfield in IDL we need to determine
      # the underlying type based on the number of bits
      if @idltype.nil?
        @idltype = IDL::Type::Boolean.new if bits == 1
        @idltype = IDL::Type::TinyShort.new if bits.between?(2,8)
        @idltype = IDL::Type::Short.new if bits.between?(9,16)
        @idltype = IDL::Type::Long.new if bits.between?(17,32)
        @idltype = IDL::Type::LongLong.new if bits.between?(33,64)
      end
      @bitset.add_bitfield(self)
    end

    def marshal_dump
      super() << @idltype << @bits << @bitset << @value
    end

    def marshal_load(vars)
      @value = vars.pop
      @bitset = vars.pop
      @bits = vars.pop
      @idltype = vars.pop
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure)
      # find already instantiated BitSet parent
      _bitmask = _enclosure.resolve(@bitset.name)
      raise "Unable to resolve instantiated BitSet scope for bitfield #{@bitset.name}::#{name} instantiation" unless _bitset

      super(instantiation_context, _enclosure, { bitset: _bitset, bits: @bits })
    end
  end # BitField

  class Typedef < Leaf
    attr_reader :idltype

    def initialize(_name, enclosure, params)
      super(_name, enclosure)
      @idltype = params[:type]
    end

    def is_local?(recurstk = [])
      @idltype.is_local?(recurstk)
    end

    def marshal_dump
      super() << @idltype
    end

    def marshal_load(vars)
      @idltype = vars.pop
      super(vars)
    end

    def instantiate(instantiation_context, _enclosure)
      super(instantiation_context, _enclosure, { type: @idltype.instantiate(instantiation_context) })
    end
  end # Typedef
end
