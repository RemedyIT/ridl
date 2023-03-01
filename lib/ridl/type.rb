#--------------------------------------------------------------------
# type.rb - IDL types
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
  class Type
    def typename
      self.class.name
    end

    def typeerror(val)
      raise "#{val.inspect} cannot narrow to #{self.typename}"
    end

    def narrow(obj)
      obj
    end

    def resolved_type
      self
    end

    def is_complete?
      true
    end

    def is_local?(recurstk = nil)
      false
    end

    def is_anonymous?
      false
    end

    def is_node?(node_class)
      false
    end

    def resolved_node
      nil
    end

    def is_template?
      false
    end

    def matches?(idltype)
      self.class == idltype.class
    end

    def instantiate(_)
      self
    end

    class UndefinedType
      def initialize(*args)
        raise "#{self.class.name}'s not implemented yet."
      end
    end

    class Void < Type
      def narrow(obj)
        typeerror(obj) unless obj.nil?
        obj
      end
    end

    class NodeType < Type
      attr_reader :node
      def initialize(node)
        raise node.inspect if node && !node.is_a?(IDL::AST::Leaf)

        @node = node
      end

      def is_local?(recurstk = nil)
        @node.is_local?
      end

      def is_node?(node_class)
        @node.is_a?(node_class)
      end

      def resolved_node
        @node
      end

      def matches?(idltype)
        super && self.resolved_node == idltype.resolved_node
      end
    end

    class ScopedName < NodeType
      def typename
        @node.name
      end

      def narrow(obj)
        @node.idltype.narrow(obj)
      end

      def resolved_type
        @node.idltype.resolved_type
      end

      def is_complete?
        resolved_type.is_complete?
      end

      def is_local?(recurstk = [])
        resolved_type.is_local?(recurstk)
      end

      def is_node?(node_class)
        @node.is_a?(IDL::AST::Typedef) ? @node.idltype.is_node?(node_class) : @node.is_a?(node_class)
      end

      def resolved_node
        @node.is_a?(IDL::AST::Typedef) ? @node.idltype.resolved_node : @node
      end

      def is_template?
        @node.is_template?
      end

      def instantiate(instantiation_context)
        if self.is_template?
          cp = IDL::AST::TemplateParam.concrete_param(instantiation_context, @node)
          cp.is_a?(Type) ? cp : ScopedName.new(cp)
        else
          self
        end
      end
    end

    class Integer < Type
      def narrow(obj)
        typeerror(obj) unless ::Integer === obj
        typeerror(obj) unless self.class::Range === obj
        obj
      end

      def self.is_unsigned?
        self::Range.first.zero?
      end

      def self.bits
        self::BITS
      end

      def range_length
        1 + (self.class::Range.last - self.class::Range.first)
      end

      def min
        self.class::Range.first
      end

      def max
        self.class::Range.last
      end

      def in_range?(val)
        val >= self.min && val <= self.max
      end

      def next(val)
        val < self.max ? val + 1 : self.min
      end

      def Integer.newclass(range, bits)
        k = Class.new(self)
        k.const_set('Range', range)
        k.const_set('BITS', bits)
        k
      end
    end
    Octet     = Integer.newclass(0..0xFF, 8)
    UShort    = Integer.newclass(0..0xFFFF, 16)
    ULong     = Integer.newclass(0..0xFFFFFFFF, 32)
    ULongLong = Integer.newclass(0..0xFFFFFFFFFFFFFFFF, 64)
    Short     = Integer.newclass(-0x8000...0x8000, 16)
    Long      = Integer.newclass(-0x80000000...0x80000000, 32)
    LongLong  = Integer.newclass(-0x8000000000000000...0x8000000000000000, 64)

    class Boolean < Type
      Range = [true, false]
      def narrow(obj)
        typeerror(obj) unless [TrueClass, FalseClass].include? obj.class
        obj
      end

      def range_length
        2
      end

      def min
        false
      end

      def max
        true
      end

      def in_range?(val)
        Range.include?(val)
      end

      def next(val)
        !val
      end
    end

    class Char < Type
      def narrow(obj)
        typeerror(obj) unless ::Integer === obj
        typeerror(obj) unless (0..255) === obj
        obj
      end

      def range_length
        256
      end

      def min
        0
      end

      def in_range?(val)
        val >= self.min && val <= self.max
      end

      def max
        255
      end

      def next(val)
        val < self.max ? val + 1 : self.min
      end
    end

    class Float < Type
      def narrow(obj)
        typeerror(obj) unless ::Float === obj
        obj
      end
    end

    class Double < Float; end
    class LongDouble < Float; end

    class Fixed < Type
      attr_reader :digits, :scale
      def initialize(digits = nil, scale = nil)
        raise "significant digits for Fixed should be in the range 0-31" unless digits.nil? || (0..31) === digits.to_i

        @digits = digits.nil? ? digits : digits.to_i
        @scale = scale.nil? ? scale : scale.to_i
      end

      def narrow(obj)
        #typeerror(obj)
        obj
      end

      def is_anonymous?
        false
      end

      def is_template?
        (@size && @size.is_a?(IDL::Expression) && @size.is_template?)
      end

      def instantiate(instantiation_context)
        self.is_template? ? (Type::Fixed.new(@size.instantiate(instantiation_context).value)) : self
      end
    end

    class String < Type
      attr_reader :size
      def length;
        @size;
      end

      def initialize(size = nil)
        @size = size
      end

      def narrow(obj)
        typeerror(obj) unless ::String === obj
        if @size.nil?
          obj
        elsif @size < obj.size
          typeerror(obj)
        else
          obj
        end
      end

      def is_anonymous?
        @size ? true : false
      end

      def is_template?
        (@size && @size.is_a?(IDL::Expression) && @size.is_template?)
      end

      def matches?(idltype)
        super && self.size == idltype.size
      end

      def instantiate(instantiation_context)
        self.is_template? ? (Type::String.new(@size.instantiate(instantiation_context).value)) : self
      end
    end

    class Sequence < Type
      attr_reader :size, :basetype
      attr_accessor :recursive
      def length;
        @size;
      end

      def initialize(t, size)
        raise "Anonymous type definitions are not allowed!" if t.is_anonymous?

        @basetype = t
        @size = size
        @typename = format("sequence<%s%s>", t.typename,
                           if @size.nil? then
                              ""
                           else
                              ", #{IDL::Expression::ScopedName === size ? size.node.name : size.to_s}"
                           end)
        @recursive = false
      end

      def typename
        @typename
      end

      def narrow(obj)
        typeerror(obj)
      end

      def is_complete?
        @basetype.resolved_type.is_complete?
      end

      def is_local?(recurstk = [])
        @basetype.resolved_type.is_local?(recurstk)
      end

      def is_recursive?
        @recursive
      end

      def is_anonymous?
        true
      end

      def is_template?
        (@size && @size.is_a?(IDL::Expression::ScopedName) && @size.node.is_a?(IDL::AST::TemplateParam)) || @basetype.is_template?
      end

      def matches?(idltype)
        super && self.size == idltype.size && self.basetype.resolved_type.matches?(idltype.basetype.resolved_type)
      end

      def instantiate(instantiation_context)
        if self.is_template?
          Type::Sequence.new(@basetype.instantiate(instantiation_context), @size ? @size.instantiate(instantiation_context).value : nil)
        else
          self
        end
      end
    end

    class Array < Type
      attr_reader :basetype
      attr_reader :sizes
      def initialize(t, sizes)
        raise "Anonymous type definitions are not allowed!" if t.is_anonymous?

        @basetype = t
        if sizes.nil?
          @sizes = []
          @typename = t.typename + "[]"
        else
          @sizes = sizes
          @typename = t.typename + sizes.collect { |s| "[#{IDL::Expression::ScopedName === s ? s.node.name : s.to_s}]" }.join
        end
      end

      def typename
        @typename
      end

      def narrow(obj)
        typeerror(obj)
      end

      def is_complete?
        @basetype.resolved_type.is_complete?
      end

      def is_local?(recurstk = [])
        @basetype.resolved_type.is_local?(recurstk)
      end

      def is_anonymous?
        true
      end

      def is_template?
        @sizes.any? { |sz| (sz.is_a?(IDL::Expression::ScopedName) && sz.node.is_a?(IDL::AST::TemplateParam)) } || @basetype.is_template?
      end

      def matches?(idltype)
        super && self.sizes == idltype.sizes && self.basetype.resolved_type.matches?(idltype.basetype.resolved_type)
      end

      def instantiate(instantiation_context)
        self.is_template? ? Type::Array.new(@basetype.instantiate(instantiation_context), @sizes.collect { |sz| sz.instantiate(instantiation_context).value }) : self
      end
    end

    class WString < Type
      attr_reader :size
      def length;
        @size;
      end

      def initialize(size = nil)
        @size = size
      end

      def narrow(obj)
        typeerror(obj) unless ::Array === obj
        if @size.nil?
          obj
        elsif @size < obj.size
          typeerror(obj)
        else
          obj
        end
      end

      def is_anonymous?
        @size ? true : false
      end

      def is_template?
        (@size && @size.is_a?(IDL::Expression::ScopedName) && @size.node.is_a?(IDL::AST::TemplateParam))
      end

      def matches?(idltype)
        super && self.size == idltype.size
      end

      def instantiate(instantiation_context)
        self.is_template? ? Type::WString.new(@size.instantiate(instantiation_context).value) : self
      end
    end

    class WChar < Type
      def narrow(obj)
        typeerror(obj) unless ::Array === obj
        typeerror(obj) unless obj.size == 2
        obj
      end
    end

    class Any < Type
    end

    class Object < Type
    end

    class ValueBase < Type
    end

    class Native < Type
    end

    class TemplateModule < NodeType
    end

    class Interface < NodeType
    end

    class Home < NodeType
    end

    class Component < NodeType
    end

    class Porttype < NodeType
    end

    class Valuebox < NodeType
      def is_local?(recurstk = [])
        node.is_local?(recurstk)
      end
    end

    class Valuetype < NodeType
      def is_complete?
        node.is_defined?
      end

      def is_local?(recurstk = [])
        node.is_local?(recurstk)
      end
    end

    class Eventtype < Valuetype
    end

    class Struct < NodeType
      def is_complete?
        node.is_defined?
      end

      def is_local?(recurstk = [])
        node.is_local?(recurstk)
      end
    end

    class Exception < Struct
    end

    class Union < NodeType
      def is_complete?
        node.is_defined?
      end

      def is_local?(recurstk = [])
        node.is_local?(recurstk)
      end
    end

    class Enum < NodeType
      def narrow(obj)
        typeerror(obj) unless ::Integer === obj
        typeerror(obj) unless (0...@node.enumerators.length) === obj
        obj
      end

      def range_length
        @node.enumerators.length
      end

      def min
        0
      end

      def max
        @node.enumerators.length - 1
      end

      def in_range?(val)
        val >= self.min && val <= self.max
      end

      def next(val)
        val < self.max ? val + 1 : self.min
      end
    end

    class Const < Type
      attr_reader :type
      def initialize(t)
        @type = t
        @typename = "const #{t.typename}"
      end

      def typename
        @typename
      end

      def narrow(obj)
        @type.narrow(obj)
      end

      def is_complete?
        @type.resolved_type.is_complete?
      end

      def is_local?(recurstk = [])
        @type.resolved_type.is_local?(recurstk)
      end

      def is_anonymous?
        t.resolved_type.is_anonymous?
      end

      def is_template?
        @type.is_template?
      end

      def instantiate(instantiation_context)
        self.is_template? ? Type::Const.new(@type.instantiate(instantiation_context)) : self
      end

      def is_node?(node_class)
        @type.is_node?(node_class)
      end

      def resolved_node
        @type.resolved_node
      end

      def matches?(idltype)
        super && self.type.resolved_type.matches?(idltype.type.resolved_type)
      end
    end

  end
end
