#--------------------------------------------------------------------
# expression.rb - IDL Expression classes
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

module IDL
  class Expression
    attr_reader :idltype
    attr_reader :value
    def typename; @idltype.typename; end

    def is_template?
      false
    end

    def instantiate(instantiation_context)
      self
    end

    class Value < Expression
      def initialize(type, val)
        @idltype = type
        @value = @idltype.narrow(val)
      end
    end

    class ScopedName < Expression
      attr_reader :node
      def initialize(node)
        if $DEBUG
          unless IDL::AST::Const === node || (IDL::AST::TemplateParam === node && node.idltype.is_a?(IDL::Type::Const))
            raise "#{node.scoped_name} must be constant: #{node.class.name}."
          end
        end
        @node = node
        @idltype = node.idltype
        @value = @idltype.narrow(node.value) unless node.is_template?
      end
      def is_template?
        @node.is_template?
      end
      def instantiate(instantiation_context)
        if self.is_template?
          cp = IDL::AST::TemplateParam.concrete_param(instantiation_context, @node)
          cp.is_a?(Expression) ? cp : ScopedName.new(cp)
        else
          self
        end
      end
      def is_node?(node_class)
        @node.is_a?(node_class)
      end
      def resolved_node
        @node
      end
    end

    class Enumerator < Expression
      attr_reader :node
      def initialize(node)
        if $DEBUG
          if not IDL::AST::Enumerator === node
            raise "#{node.scoped_name} must be enumerator: #{node.class.name}."
          end
        end
        @node = node
        @idltype = node.idltype
        @value = node.value
      end
    end

    class Operation < Expression
      NUMBER_OF_OPERANDS = nil

      attr_reader :operands
      def initialize(*_operands)
        n = self.class::NUMBER_OF_OPERANDS

        if _operands.size != n
          raise format("%s must receive %d operand%s.",
            self.typename, n, if (n>1) then "s" else "" end)
        end

        unless _operands.any? { |o| o.is_template? }
          @idltype = self.class.suite_type(*(_operands.collect{|o| o.idltype.resolved_type}))
          @value = calculate(*(_operands.collect{|o| o.value}))
        else
          @idltype = nil
          @value = nil
        end
        @operands = _operands
        self.set_type
      end

      def is_template?
        @operands.any? { |o| o.is_template? }
      end

      def instantiate(instantiation_context)
        self.is_template? ? self.class.new(*@operands.collect { |o| o.instantiate(instantiation_context) }) : self
      end

      def Operation.suite_type(*types)
        types.each do |t|
          if not self::Applicable.include? t.class
            raise "#{self.name} cannot be applicable for #{t.typename}"
          end
        end

        ret = nil
        types = types.collect {|t| t.class }
        self::Applicable.each do |t|
          if types.include? t
            ret = t
            break
          end
        end
        ret
      end
      def set_type
      end

      class Unary < Operation
        NUMBER_OF_OPERANDS = 1
        Applicable = nil
      end #of class Unary

      class Integer2 < Operation
        NUMBER_OF_OPERANDS = 2
        Applicable = [
          IDL::Type::LongLong, IDL::Type::ULongLong,
          IDL::Type::Long, IDL::Type::ULong,
          IDL::Type::Short, IDL::Type::UShort,
          IDL::Type::Octet
        ]

        def Integer2.suite_sign(_t, _v)
          [ [IDL::Type::LongLong, IDL::Type::ULongLong],
            [IDL::Type::Long,     IDL::Type::ULong],
            [IDL::Type::Short,    IDL::Type::UShort]
          ].each do |t|
            next unless t.include? _t
            return (if _v < 0 then t[0] else t[1] end)
          end
        end

        def set_type
          if Integer2::Applicable.include? @idltype
            @idltype = self.class.suite_sign(@idltype, @value)
          end
        end
      end

      class Boolean2 < Integer2
        Applicable = [
          IDL::Type::Boolean
        ] + Integer2::Applicable

        def Boolean2.checktype(t1, t2)
          superclass.checktype(*types)

          t = IDL::Type::Boolean
          if (t1 == t && t2 != t) or (t1 != t && t2 == t)
            raise "#{self.name} about #{t1.typename} and #{t2.typename} is illegal."
          end
        end
      end

      class Float2 < Integer2
        Applicable = [
          IDL::Type::LongDouble, IDL::Type::Double, IDL::Type::Float,
          IDL::Type::Fixed
        ] + Integer2::Applicable

        def Float2.checktype(t1, t2)
          superclass.checktype(*types)

          # it's expected that Double, LongDouble is a Float.
          s1,s2 = IDL::Type::Float, IDL::Type::Fixed
          if (t1 === s1 && t2 === s2) or (t1 === s2 && t2 === s1)
            raise "#{self.name} about #{t1.typename} and #{t2.typename} is illegal."
          end
        end
      end

      class UnaryPlus < Unary
        Applicable = Float2::Applicable
        def calculate(op)
          op
        end
      end
      class UnaryMinus < Unary
        Applicable = Float2::Applicable
        def calculate(op)
          -op
        end
        def set_type
          @idltype = Integer2.suite_sign(@idltype, @value)
        end
      end
      class UnaryNot < Unary
        Applicable = Integer2::Applicable
        def calculate(op)
          if @idltype.is_unsigned?()
            (2**@idltype.bits-1)-op
          else
            ~op
          end
        end
      end

      class Or < Boolean2
        def calculate(lop,rop); lop | rop; end
      end
      class And < Boolean2
        def calculate(lop,rop); lop & rop; end
      end
      class Xor < Boolean2
        def calculate(lop,rop); lop ^ rop; end
      end

      class Shift < Integer2
      protected
        def check_rop(rop)
          if not (0...64) === rop
            raise "right operand for shift must be in the range 0 <= right operand < 64: #{rop}."
          end
        end
      end
      class LShift < Shift
        def calculate(lop,rop)
          check_rop(rop)
          lop << rop
        end
      end
      class RShift < Shift
        def calculate(lop,rop)
          check_rop(rop)
          lop >> rop
        end
      end

      class Add < Float2
        def calculate(lop,rop); lop + rop; end
      end
      class Minus < Float2
        def calculate(lop,rop); lop - rop; end
      end
      class Mult < Float2
        def calculate(lop,rop); lop * rop; end
      end
      class Div < Float2
        def calculate(lop,rop); lop / rop; end
      end
      class Mod < Integer2
        def calculate(lop,rop); lop % rop; end
      end
    end #of class Operation
  end #of class Expression
end
