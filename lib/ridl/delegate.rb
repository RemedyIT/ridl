#--------------------------------------------------------------------
# delegate.rb - IDL delegator
#
# Author: Martin Corino
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the RIDL LICENSE which is
# included with this program.
#
# Copyright (c) Remedy IT Expertise BV
#--------------------------------------------------------------------
require 'ridl/node'
require 'ridl/expression'

module IDL
ORB_PIDL = 'orb.pidlc'.freeze

class Delegator

  # #pragma handler registry
  # each keyed entry a callable object:
  # - responds to #call(delegator, cur_node, pragma_string)
  # - returns boolean to indicate pragma recognized and handled (true) or not (false)
  @@pragma_handlers = {}

  def self.add_pragma_handler(key, h = nil, &block)
    raise 'add_pragma_handler requires a callable object or a block' unless h&.respond_to?(:call) || block_given?

    @@pragma_handlers[key] = block_given? ? block : h
  end

  def self.get_pragma_handler(key)
    @@pragma_handlers[key]
  end

  def initialize(params = {})
    @annotation_stack = IDL::AST::Annotations.new
    @includes = {}
    @expand_includes = params[:expand_includes] || false
    @preprocess = params[:preprocess] || false
    @preprocout = params[:output] if @preprocess
    @ignore_pidl = params[:ignore_pidl] || false
    @root_namespace = nil
    unless params[:namespace].nil?
      @root_namespace = IDL::AST::Module.new(params[:namespace], nil, {})
    end
  end

  attr_reader :root, :root_namespace

  def pre_parse
    @root = nil
    unless @preprocess || @ignore_pidl
      IDL.backend.lookup_path.each do |be_root|
        pidl_file = File.join(be_root, ORB_PIDL)
        if File.file?(pidl_file) && File.readable?(pidl_file)
          f = File.open(pidl_file, 'r')
          begin
            @root, @includes = Marshal.load(f)
            @cur = @root
          rescue Exception => ex
            IDL.error("RIDL - failed to load ORB pidlc [#{ex}]\n You probably need to rebuild the bootstrap file (compile orb.idl to orb.pidlc).")
            exit(1)
          ensure
            f.close
          end
          break
        end
      end
      return if @root
    end
    @root = @cur = IDL::AST::Module.new(nil, nil, {}) # global root
    @last = nil
    @last_pos = nil
  end

  def post_parse
    if @preprocess
      Marshal.dump([@root, @includes], @preprocout)
    end
  end

  private

  def set_last(node = nil)
    @last = node
    @last_pos = @scanner.position.dup if node
    node
  end

  public

  def visit_nodes(walker)
    walker.visit_nodes(self)
  end

  def walk_nodes(walker, root_node = nil)
    (root_node || @root).walk_members { |m| walk_member(m, walker) }
  end

  def walk_member(m, w)
    case m
    when IDL::AST::Include
      unless m.is_preprocessed?
        if @expand_includes
          if m.is_defined?
            w.enter_include(m)
            m.walk_members { |cm| walk_member(cm, w) }
            w.leave_include(m)
          end
        else
          w.visit_include(m)
        end
      end
    when IDL::AST::Porttype, IDL::AST::TemplateModule
      # these are template types and do not generally generate
      # code by themselves but only when 'instantiated' (used)
      # in another type
    when IDL::AST::Module
      w.enter_module(m)
      m.walk_members { |cm| walk_member(cm, w) }
      w.leave_module(m)
    when IDL::AST::Interface
      if m.is_forward?
        w.declare_interface(m)
      else
        w.enter_interface(m)
        m.walk_members { |cm| walk_member(cm, w) }
        w.leave_interface(m)
      end
    when IDL::AST::Home
      _te = w.respond_to?(:enter_home)
      _tl = w.respond_to?(:leave_home)
      return unless _te || _tl

      w.enter_home(m) if _te
      m.walk_members { |cm| walk_member(cm, w) }
      w.leave_home(m) if _tl
    when IDL::AST::Component
      if m.is_forward?
        w.declare_component(m) if w.respond_to?(:declare_component)
      else
        _te = w.respond_to?(:enter_component)
        _tl = w.respond_to?(:leave_component)
        return unless _te || _tl

        w.enter_component(m) if _te
        m.walk_members { |cm| walk_member(cm, w) }
        w.leave_component(m) if _tl
      end
    when IDL::AST::Connector
      _te = w.respond_to?(:enter_connector)
      _tl = w.respond_to?(:leave_connector)
      return unless _te || _tl

      w.enter_connector(m) if _te
      m.walk_members { |cm| walk_member(cm, w) }
      w.leave_connector(m) if _tl
    when IDL::AST::Port
      w.visit_port(m) if w.respond_to?(:visit_port)
    when IDL::AST::Valuebox
      w.visit_valuebox(m)
    when IDL::AST::Valuetype, IDL::AST::Eventtype
      if m.is_forward?
        w.declare_valuetype(m)
      else
        w.enter_valuetype(m)
        m.walk_members { |cm| walk_member(cm, w) }
        w.leave_valuetype(m)
      end
    when IDL::AST::Finder
      w.visit_finder(m) if w.respond_to?(:visit_finder)
    when IDL::AST::Initializer
      w.visit_factory(m) if w.respond_to?(:visit_factory)
    when IDL::AST::Const
      w.visit_const(m)
    when IDL::AST::Operation
      w.visit_operation(m)
    when IDL::AST::Attribute
      w.visit_attribute(m)
    when IDL::AST::Exception
      w.enter_exception(m)
      m.walk_members { |cm| walk_member(cm, w) }
      w.leave_exception(m)
    when IDL::AST::Struct
      if m.is_forward?
        w.declare_struct(m)
      else
        w.enter_struct(m)
        m.walk_members { |cm| walk_member(cm, w) }
        w.leave_struct(m)
      end
    when IDL::AST::Union
      if m.is_forward?
        w.declare_union(m)
      else
        w.enter_union(m)
        m.walk_members { |cm| walk_member(cm, w) }
        w.leave_union(m)
      end
    when IDL::AST::Typedef
      w.visit_typedef(m)
    when IDL::AST::Enum
      w.visit_enum(m)
    when IDL::AST::Enumerator
      w.visit_enumerator(m)
    else
      raise "Invalid IDL member type for walkthrough: #{m.class.name}"
    end
  end

  def is_included?(s)
    @includes.has_key?(s)
  end

  def enter_include(s, fullpath)
    params = { filename: s, fullpath: fullpath }
    params[:defined] = true
    params[:preprocessed] = @preprocess
    @cur = @cur.define(IDL::AST::Include, "$INC:" + s, params)
    @includes[s] = @cur
    set_last
    @cur
  end

  def leave_include()
    set_last
    @cur = @cur.enclosure
  end

  def declare_include(s)
    params = { filename: s, fullpath: @includes[s].fullpath }
    params[:defined] = false
    params[:preprocessed] = @includes[s].is_preprocessed?
    @cur.define(IDL::AST::Include, "$INC:" + s, params)
  end

  def pragma_prefix(s)
    @cur.prefix = s
  end

  def pragma_version(id, major, minor)
    ids = id.split('::')
    global = false
    if ids.first.empty?
      global = true
      ids.shift
    end
    t = parse_scopedname(global, ids)
    t.node.set_repo_version(major, minor)
  end

  def pragma_id(id, repo_id)
    ids = id.split('::')
    global = false
    if ids.first.empty?
      global = true
      ids.shift
    end
    t = parse_scopedname(global, ids)
    t.node.set_repo_id(repo_id)
  end

  def handle_pragma(pragma_string)
    unless @@pragma_handlers.values.reduce(false) { |rc, h| h.call(self, @cur, pragma_string) || rc }
      IDL.log(1, "RIDL - unrecognized pragma encountered: #{pragma_string}.")
    end
  end

  def define_typeprefix(type, pfx)
    type.node.replace_prefix(pfx.to_s)
  end

  def define_typeid(type, tid)
    type.node.set_repo_id(tid.to_s)
  end

  def define_annotation(annid, annpos, anncomment, annbody)
    IDL.log(3, "parsed #{anncomment ? 'commented ' : ''}Annotation #{annid}(#{annbody}) @ #{annpos}")
    if anncomment && @last && (@last_pos.line == annpos.line) && (@last_pos.name == annpos.name)
      IDL.log(3, 'adding annotation to last node')
      @last.annotations << IDL::AST::Annotation.new(annid, annbody)
    else
      IDL.log(3, 'appending annotation cached stack')
      @annotation_stack << IDL::AST::Annotation.new(annid, annbody)
    end
  end

  def define_module(name)
    @cur = @cur.define(IDL::AST::Module, name)
    @cur.annotations.concat(@annotation_stack)
    @annotation_stack = IDL::AST::Annotations.new
    set_last
    @cur
  end

  def end_module(_node)
    set_last(@cur)
    @cur = @cur.enclosure # must equals to argument mod
  end

  def register_template_module_name(name_spec)
    @template_module_name = name_spec
  end

  def define_template_module(global, names)
    if global || names.size > 1
      raise "no scoped identifier allowed for template module: #{(global ? '::' : '') + names.join('::')}"
    end

    @cur = @cur.define(IDL::AST::TemplateModule, names[0])
    @cur.annotations.concat(@annotation_stack)
    @annotation_stack = IDL::AST::Annotations.new
    set_last
    @cur
  end
  alias :end_template_module :end_module

  def define_template_parameter(name, type)
    if @template_module_name
      tmp = @template_module_name
      @template_module_name = nil # reset
      define_template_module(*tmp)
    end
    params = { type: type }
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last(@cur.define(IDL::AST::TemplateParam, name, params))
    @cur
  end

  def instantiate_template_module(name, parameters)
    tmp = @template_module_name
    @template_module_name = nil # reset
    template_type = parse_scopedname(*tmp)
    unless template_type.node.is_a?(IDL::AST::TemplateModule)
      raise "invalid module template specification: #{template_type.node.typename} #{template_type.node.scoped_lm_name}"
    end

    params = { template: template_type.node, template_params: parameters }
    mod_inst = @cur.define(IDL::AST::Module, name, params)
    mod_inst.annotations.concat(@annotation_stack)
    @annotation_stack = IDL::AST::Annotations.new
    set_last(mod_inst.template.instantiate(mod_inst))
    @cur
  end

  def declare_template_reference(name, type, tpl_params)
    params = {}
    params[:tpl_type] = type
    params[:tpl_params] = tpl_params || []
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last(@cur.define(IDL::AST::TemplateModuleReference, name, params))
    @cur
  end

  def declare_interface(name, attrib = nil)
    params = {}
    params[:abstract] = attrib == :abstract
    params[:local] = attrib == :local
    params[:forward] = true
    params[:pseudo] = false
    raise "annotations with forward declaration of #{name} not allowed" unless @annotation_stack.empty?

    @cur.define(IDL::AST::Interface, name, params)
    set_last
    @cur
  end

  def define_interface(name, attrib, inherits = [])
    params = {}
    params[:abstract] = attrib == :abstract
    params[:local] = attrib == :local
    params[:pseudo] = attrib == :pseudo
    params[:forward] = false
    params[:inherits] = inherits
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last
    @cur = @cur.define(IDL::AST::Interface, name, params)
  end

  def end_interface(_node)
    set_last(@cur)
    @cur = @cur.enclosure # must equals to argument mod
  end

  def define_home(name, base, component, key = nil, supports = nil)
    params = {}
    params[:base] = base
    params[:component] = component
    params[:key] = key
    params[:supports] = supports || []
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last
    @cur = @cur.define(IDL::AST::Home, name, params)
  end

  def end_home(_node)
    set_last(@cur)
    @cur = @cur.enclosure
  end

  def declare_component(name)
    params = {}
    params[:forward] = true
    raise "annotations with forward declaration of #{name} not allowed" unless @annotation_stack.empty?

    set_last
    @cur.define(IDL::AST::Component, name, params)
  end

  def define_component(name, base, supports = nil)
    params = {}
    params[:base] = base
    params[:supports] = supports || []
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last
    @cur = @cur.define(IDL::AST::Component, name, params)
  end

  def end_component(_node)
    set_last(@cur)
    @cur = @cur.enclosure
  end

  def define_connector(name, base = nil)
    params = {}
    params[:base] = base
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last
    @cur = @cur.define(IDL::AST::Connector, name, params)
  end

  def end_connector(_node)
    set_last(@cur)
    @cur = @cur.enclosure
  end

  def define_porttype(name)
    params = {}
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last
    @cur = @cur.define(IDL::AST::Porttype, name, params)
  end

  def end_porttype(_node)
    set_last(@cur)
    @cur = @cur.enclosure
  end

  def declare_port(name, porttype, type, multiple = false)
    params = {}
    params[:porttype] = porttype
    params[:type] = type
    params[:multiple] = multiple
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last(@cur.define(IDL::AST::Port, name, params))
    @cur
  end

  def declare_eventtype(name, attrib = nil)
    params = {}
    params[:abstract] = attrib == :abstract
    params[:forward] = true
    raise "annotations with forward declaration of #{name} not allowed" unless @annotation_stack.empty?

    set_last
    @cur.define(IDL::AST::Eventtype, name, params)
    @cur
  end

  def define_eventtype(name, attrib, inherits = {})
    params = {}
    params[:abstract] = attrib == :abstract
    params[:custom] = attrib == :custom
    params[:forward] = false
    params[:inherits] = inherits
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last
    @cur = @cur.define(IDL::AST::Eventtype, name, params)
    @cur
  end

  def declare_valuetype(name, attrib = nil)
    params = {}
    params[:abstract] = attrib == :abstract
    params[:forward] = true
    raise "annotations with forward declaration of #{name} not allowed" unless @annotation_stack.empty?

    set_last
    @cur.define(IDL::AST::Valuetype, name, params)
    @cur
  end

  def define_valuetype(name, attrib, inherits = {})
    params = {}
    params[:abstract] = attrib == :abstract
    params[:custom] = attrib == :custom
    params[:forward] = false
    params[:inherits] = inherits
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last
    @cur = @cur.define(IDL::AST::Valuetype, name, params)
    @cur
  end

  def end_valuetype(node)
    node.defined = true
    set_last(@cur)
    ret = IDL::Type::ScopedName.new(@cur)
    @cur = @cur.enclosure # must equals to argument mod
    ret
  end
  alias :end_eventtype :end_valuetype

  def declare_state_member(type, name, public_)
    params = {}
    params[:type] = type
    params[:visibility] = (public_ ? :public : :private)
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last(@cur.define(IDL::AST::StateMember, name, params))
    @cur
  end

  def define_valuebox(name, type)
    params = { type: type }
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last(@cur.define(IDL::AST::Valuebox, name, params))
    @cur
  end

  def declare_initializer(name, params_, raises_)
    params = {}
    params[:params] = params_
    params[:raises] = raises_
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last(@cur.define(IDL::AST::Initializer, name, params))
    @cur
  end

  def declare_finder(name, params_, raises_)
    params = {}
    params[:params] = params_
    params[:raises] = raises_
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last(@cur.define(IDL::AST::Finder, name, params))
    @cur
  end

  def parse_scopedname(global, namelist)
    node = root = if global then @root else @cur end
    first = nil
    namelist.each do |nm|
      n = node.resolve(nm)
      if n.nil?
        raise "cannot find type name '#{nm}' in scope '#{node.scoped_name}'"
      end

      node = n
      first = node if first.nil?
    end
    root.introduce(first)
    case node
    when IDL::AST::Module, IDL::AST::TemplateModule,
         IDL::AST::Interface, IDL::AST::Home, IDL::AST::Component,
         IDL::AST::Porttype, IDL::AST::Connector,
         IDL::AST::Struct, IDL::AST::Union, IDL::AST::Typedef,
         IDL::AST::Exception, IDL::AST::Enum,
         IDL::AST::Valuetype, IDL::AST::Valuebox
      Type::ScopedName.new(node)
    when IDL::AST::TemplateParam
      if node.idltype.is_a?(IDL::Type::Const)
        Expression::ScopedName.new(node)
      else
        Type::ScopedName.new(node)
      end
    when IDL::AST::Const
      Expression::ScopedName.new(node)
    when IDL::AST::Enumerator
      Expression::Enumerator.new(node)
    else
      raise "invalid reference to #{node.class.name}: #{node.scoped_name}"
    end
  end

  def parse_literal(_typestring, _value)
    k = Expression::Value
    case _typestring
    when :boolean
      k.new(Type::Boolean.new, _value)
    when :integer
      _type = [
        Type::Octet,
        Type::Short,
        Type::Long,
        Type::LongLong,
        Type::ULongLong,
      ].detect { |t| t::Range === _value }
      if _type.nil?
        raise "it's not a valid integer: #{v.to_s}"
      end

      k.new(_type.new, _value)
    when :string
      k.new(Type::String.new, _value)
    when :wstring
      k.new(Type::WString.new, _value)
    when :char
      k.new(Type::Char.new, _value)
    when :wchar
      k.new(Type::WChar.new, _value)
    when :fixed
      k.new(Type::Fixed.new, _value)
    when :float
      k.new(Type::Float.new, _value)
    else
      raise ParseError, "unknown literal type: #{type}"
    end
  end

  def parse_positive_int(_expression)
    if _expression.is_template?
      _expression
    else
      if not ::Integer === _expression.value
        raise "must be integer: #{_expression.value.inspect}"
      elsif _expression.value.negative?
        raise "must be positive integer: #{_expression.value.to_s}"
      end

      _expression.value
    end
  end

  def define_const(_type, _name, _expression)
    params = { type: _type, expression: _expression }
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last(@cur.define(IDL::AST::Const, _name, params))
    @cur
  end

  def declare_op_header(_oneway, _type, _name)
    params = {}
    params[:oneway] = (_oneway == :oneway)
    params[:type]   = _type
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last
    @cur = @cur.define(IDL::AST::Operation, _name, params)
  end

  def declare_op_parameter(_attribute, _type, _name)
    params = {}
    params[:attribute] = _attribute
    params[:type] = _type
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last(@cur.define(IDL::AST::Parameter, _name, params))
    @cur
  end

  def declare_op_footer(_raises, instantiation_context)
    @cur.raises = _raises || []
    @cur.context = instantiation_context
    unless @cur.context.nil?
      raise "context phrase's not supported"
    end

    set_last(@cur)
    @cur = @cur.enclosure
  end

  def declare_attribute(_type, _name, _readonly = false)
    params = {}
    params[:type] = _type
    params[:readonly] = _readonly
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last(@cur.define(IDL::AST::Attribute, _name, params))
  end

  def declare_struct(_name)
    params = { forward: true }
    raise "annotations with forward declaration of #{name} not allowed" unless @annotation_stack.empty?

    set_last
    @cur.define(IDL::AST::Struct, _name, params)
    @cur
  end

  def define_struct(_name)
    params = { forward: false }
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last
    @cur = @cur.define(IDL::AST::Struct, _name, params)
  end

  def declare_member(_type, _name)
    params = {}
    params[:type] = _type
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last(@cur.define(IDL::AST::Member, _name, params))
    @cur
  end

  def end_struct(node)
    node.defined = true
    set_last(@cur)
    ret = IDL::Type::ScopedName.new(@cur)
    @cur = @cur.enclosure
    ret
  end

  def define_exception(_name)
    params = { forward: false }
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last
    @cur = @cur.define(IDL::AST::Exception, _name, params)
  end

  def end_exception(_node)
    set_last(@cur)
    ret = IDL::Type::ScopedName.new(@cur)
    @cur = @cur.enclosure
    ret
  end

  def declare_union(_name)
    params = { forward: true }
    raise "annotations with forward declaration of #{name} not allowed" unless @annotation_stack.empty?

    set_last
    @cur.define(IDL::AST::Union, _name, params)
    @cur
  end

  def define_union(_name)
    params = { forward: false }
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last
    @cur = @cur.define(IDL::AST::Union, _name, params)
  end

  def define_union_switchtype(union_node, switchtype)
    union_node.set_switchtype(switchtype)
    union_node.annotations.concat(@annotation_stack)
    @annotation_stack = IDL::AST::Annotations.new
    union_node
  end

  def define_case(_labels, _type, _name)
    params = {}
    params[:type] = _type
    params[:labels] = _labels
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last(@cur.define(IDL::AST::UnionMember, _name, params))
    @cur
  end

  def end_union(node)
    node.validate_labels
    node.defined = true
    set_last(@cur)
    ret = IDL::Type::ScopedName.new(@cur)
    @cur = @cur.enclosure
    ret
  end

  def define_enum(_name)
    params = {}
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last
    @cur = @cur.define(IDL::AST::Enum, _name, params)
  end

  def declare_enumerator(_name)
    n = @cur.enumerators.length
    params = {
      value: n,
      enum: @cur
    }
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last(@cur.enclosure.define(IDL::AST::Enumerator, _name, params))
    @cur
  end

  def end_enum(_node)
    set_last(@cur)
    ret = IDL::Type::ScopedName.new(@cur)
    @cur = @cur.enclosure
    ret
  end

  def declare_typedef(_type, _name)
    params = {}
    params[:type] = _type
    params[:annotations] = @annotation_stack
    @annotation_stack = IDL::AST::Annotations.new
    set_last(@cur.define(IDL::AST::Typedef, _name, params))
    @cur
  end
end # Delegator
end # IDL
