#--------------------------------------------------------------------
# writer.rb - IDL backend writers
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
  class TestWriterBase
    def initialize(output = STDOUT, params = {}, indent = "  ")
      @output = output
      @params = params
      @indent = indent
      @nest = 0
    end

    def print(str); @output << str; end

    def println(str = "");  @output << str << "\n"; end

    def printi(str = "");   @output << indent << str; end

    def printiln(str = ""); @output << indent << str << "\n"; end

    def indent()
      @indent * @nest
    end

    def nest(in_ = 1)
      @nest += in_
      begin
        yield
      ensure
        @nest -= in_
      end
    end

    def inc_nest(in_ = 1)
      @nest += in_
    end

    def dec_nest(in_ = 1)
      @nest -= in_
    end

    def visit_nodes(parser)
      pre_visit(parser)

      parser.walk_nodes(self)

      post_visit(parser)
    end
  end

  class TestStubWriter < TestWriterBase
    def initialize(output = STDOUT, params = {}, indent = "  ")
      super
    end

    def pre_visit(parser)
      println(%Q{# -*- Test Client Stub Writer -*-})
      println(%Q{# File: #{@params[:idlfile]}})
      inc_nest
    end

    def post_visit(parser)
      dec_nest
      println('# -*- END Client Stub Writer -*-')
    end

    def visit_include(node)
      println("- include '#{node.filename}'")
    end

    def enter_include(node)
      printiln("> include #{node.filename}")
      inc_nest
    end

    def leave_include(node)
      dec_nest
      printiln("< include #{node.filename}")
    end

    def enter_module(node)
      printiln("> module #{node.lm_name}")
      inc_nest
      if node.is_templated?
        printiln("template: #{node.template.scoped_name}")
        node.template_params.each_with_index do |p, i|
          printiln("- #{node.template.params[i].name}: #{p.node.scoped_name}")
        end
      end
    end

    def leave_module(node)
      dec_nest
      printiln("< module #{node.lm_name}")
    end

    def declare_interface(node)
      println("- interface #{node.lm_name}")
    end

    def enter_interface(node)
      printiln("> interface #{node.lm_name}")
      inc_nest
    end

    def leave_interface(node)
      dec_nest
      printiln("< interface #{node.lm_name}")
    end

    def declare_valuetype(node)
      println("- valuetype #{node.lm_name}")
    end

    def enter_valuetype(node)
      printiln("> valuetype #{node.lm_name}")
      inc_nest
    end

    def leave_valuetype(node)
      dec_nest
      printiln("< valueype #{node.lm_name}")
    end

    def visit_valuebox(node)
      println("+ valuebox #{node.lm_name}")
    end

    def visit_const(node)
      println("+ const #{node.lm_name} = #{expression_to_s(node.expression)}")
    end

    def visit_operation(node, from_valuetype = false)
      println("+  op #{node.lm_name}")
    end

    def visit_attribute(node, from_valuetype = false)
      println("+  att #{node.lm_name}")
    end

    def expression_to_s(exp)
      case exp
      when Expression::Value
        value_to_s(exp)
      when Expression::Operation
        operation_to_s(exp)
      when Expression::ScopedName, Expression::Enumerator
        exp.node.scoped_rubyname
      else
        raise "unknown expression type: #{exp.class.name}"
      end
    end

    def value_to_s(exp)
      s = nil
      v = exp.value
      case exp.idltype
      when Type::Void
        s = "nil"
      when Type::Char
        s = "'#{v.chr}'"
      when Type::Integer,
          Type::Boolean,
          Type::Octet,
          Type::Float
        s = v.to_s
      when Type::WChar
        s = (case v.first
             when :char, :esc_ch
               v.last.unpack('c')
             when :esc
               IDL::Scanner::ESCTBL[v.last]
             when :oct
               v.last.oct
             when :hex2, :hex4
               v.last.hex
             else
               0
             end).to_s
      when Type::Enum
        v = exp.idltype.narrow(v)
        s = exp.idltype.node.enumerators[v].scoped_rubyname
      when Type::String
        s = "'#{v.to_s}'"
      when Type::WString
        v = (v.collect do |(elt, elv)|
          case elt
          when :char, :esc_ch
            elv.unpack('c')
          when :esc
            IDL::Scanner::ESCTBL[elv]
          when :oct
            elv.oct
          when :hex2, :hex4
            elv.hex
          else
            nil
          end
        end).compact
        s = "[#{v.join(',')}]"
        # when Type::Fixed
        # when Type::Any
        # when Type::Object
      when Type::ScopedName
        s = value_to_s(Expression::Value.new(exp.idltype.node.idltype, v))
      else
        raise "#{exp.typename}'s not been supported yet."
      end
      s
    end

    def operation_to_s(exp)
      s = nil
      op = exp.operands
      case exp
      when Expression::Operation::UnaryPlus
        s = expression_to_s(op[0])
      when Expression::Operation::UnaryMinus
        s = "-" + expression_to_s(op[0])
      when Expression::Operation::UnaryNot
        s = "~" + expression_to_s(op[0])
      when Expression::Operation::Or
        s = expression_to_s(op[0]) + " | " + expression_to_s(op[1])
      when Expression::Operation::And
        s = expression_to_s(op[0]) + " & " + expression_to_s(op[1])
      when Expression::Operation::LShift
        s = expression_to_s(op[0]) + " << " + expression_to_s(op[1])
      when Expression::Operation::RShift
        s = expression_to_s(op[0]) + " >> " + expression_to_s(op[1])
      when Expression::Operation::Add
        s = expression_to_s(op[0]) + " + " + expression_to_s(op[1])
      when Expression::Operation::Minus
        s = expression_to_s(op[0]) + " - " + expression_to_s(op[1])
      when Expression::Operation::Mult
        s = expression_to_s(op[0]) + " * " + expression_to_s(op[1])
      when Expression::Operation::Div
        s = expression_to_s(op[0]) + " / " + expression_to_s(op[1])
      when Expression::Operation::Mod
        s = expression_to_s(op[0]) + " % " + expression_to_s(op[1])
      else
        raise "unknown operation: #{exp.type.name}"
      end
      "(" + s + ")"
    end

    def declare_struct(node)
      println("- struct #{node.lm_name}")
    end

    def enter_struct(node)
      printiln("> struct " + node.lm_name)
      inc_nest
      node.members.each do |m|
        if IDL::Type::NodeType === m.idltype
          printiln("- #{m.name}: #{m.idltype.node.scoped_name}")
        else
          printiln("- #{m.name}: #{m.idltype.typename}")
        end
      end
    end

    def leave_struct(node)
      dec_nest
      printiln("< struct #{node.lm_name}")
    end

    def enter_exception(node)
      printiln("> exception #{node.lm_name}")
      inc_nest
    end

    def leave_exception(node)
      dec_nest
      printiln("< exception #{node.lm_name}")
    end

    def declare_union(node)
      println("- union #{node.lm_name}")
    end

    def enter_union(node)
      printiln("> union #{node.lm_name}")
      inc_nest
    end

    def leave_union(node)
      dec_nest
      printiln("< union #{node.lm_name}")
    end

    def visit_enum(node)
      println("- enum #{node.lm_name}")
    end

    def visit_enumerator(node)
      v = Expression::Value.new(node.idltype, node.value)
      println("+ enumerator #{node.lm_name} = #{expression_to_s(v)}")
    end

    def visit_typedef(node)
      println("- typedef #{node.lm_name}")
    end
  end ## TestStubWriter

  class TestServantWriter < TestWriterBase
    def initialize(output = STDOUT, params = {}, indent = "  ")
      super
    end

    def pre_visit(parser)
      println(%Q{# -*- Test Servant Writer -*-})
      println(%Q{# File: #{@params[:idlfile]}})
      inc_nest
    end

    def post_visit(parser)
      dec_nest
      println('# -*- END Servant Writer -*-')
    end

    def visit_include(node)
      println("- include '#{node.filename}'")
    end

    def enter_include(node)
      printiln("> include #{node.filename}")
      inc_nest
    end

    def leave_include(node)
      dec_nest
      printiln("< include #{node.filename}")
    end

    def enter_module(node)
      printiln("> module #{node.lm_name}")
      inc_nest
    end

    def leave_module(node)
      dec_nest
      printiln("< module #{node.lm_name}")
    end

    def declare_interface(node)
      println("- interface #{node.lm_name}")
    end

    def enter_interface(node)
      printiln("> interface " + node.lm_name)
      inc_nest
    end

    def leave_interface(node)
      dec_nest
      printiln("< interface #{node.lm_name}")
    end

    def declare_valuetype(node)
      println("- valuetype #{node.lm_name}")
    end

    def enter_valuetype(node)
      printiln("> valuetype #{node.lm_name}")
      inc_nest
    end

    def leave_valuetype(node)
      dec_nest
      printiln("< valueype #{node.lm_name}")
    end

    def visit_valuebox(node); end

    def visit_const(node); end

    def visit_operation(node, from_valuetype = false)
      println("+  op #{node.lm_name}")
    end

    def visit_attribute(node, from_valuetype = false)
      println("+  att #{node.lm_name}")
    end

    def declare_struct(node); end
    def enter_struct(node); end
    def leave_struct(node); end

    def enter_exception(node); end
    def leave_exception(node); end

    def declare_union(node); end
    def enter_union(node); end
    def leave_union(node); end

    def visit_enum(node); end

    def visit_enumerator(node); end

    def visit_typedef(node); end
  end ## TestServantWriter
end # IDL
