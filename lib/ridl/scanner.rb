#--------------------------------------------------------------------
# scanner.rb - IDL scanner
#
# Author: Martin Corino
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the RIDL LICENSE which is
# included with this program.
#
# Copyright (c) Remedy IT Expertise BV
#--------------------------------------------------------------------
require 'delegate'

module IDL
  class ParseError < StandardError
    attr_reader :positions

    def initialize(msg, positions)
      super(msg)
      @positions = positions
    end

    def inspect
      puts "#{self.class.name}: #{message}"
      @positions.each { |pos|
        print '    '
        puts pos
      }
      nil
    end
  end

  class Scanner
    Position = Struct.new(nil, :name, :line, :column)

    class Position
      def to_s
        format('%s: line %d, column %d', name.to_s, line, column)
      end

      def inspect
        to_s
      end
    end ## Position

    class In
      def initialize(src, name = '', line = 0, column = 1)
        @src = src
        @fwd = src.getc     # look ahead character
        @bwd = nil          # look back character
        @pos = Position.new(name, line, column)
        @mark = nil
      end

      def position
        @pos
      end

      def column
        @pos.column
      end

      # cursor set at last gotten character.
      # ex: after initialization, position is (0,0).
      def to_s
        @src.to_s
      end

      def lookc
        @fwd
      end

      def getc
        cur = @fwd
        @fwd = @src.getc unless @src.nil?
        @mark << cur unless @mark.nil?
        if [nil, "\n", "\r"].include? @bwd
          if @bwd == "\r" and cur == "\n"
          else
            @pos.line += 1
            @pos.column = 1
          end
        else
          @pos.column += 1
        end

        if false
          if not @bwd.nil? or cur.nil? or @fwd.nil?
          printf("%c(%02x), %c(%02x), %c(%02x) @(l:%d,c:%d)\n",
                @bwd, @bwd, cur, cur, @fwd, @fwd, @pos.line, @pos.column)
          end
        end
        @bwd = cur
      end

      def gets
        return nil if @fwd.nil?

        s = ''
        s << getc until [nil, "\n", "\r"].include? lookc
        s << getc while ["\n", "\r"].include? lookc

        @mark << s unless @mark.nil?
        s
      end
      alias skipc getc

      def skipwhile(*_chars, &block)
        if block
          until (ch = lookc).nil?
            return ch unless block.call(ch)

            skipc
          end
        end
        nil
      end

      def skipuntil(*_chars, &block)
        if block
          until (ch = lookc).nil?
            return ch if block.call(ch)

            skipc
          end
        end
        nil
      end

      def mark(*ini)
        @mark = ''
        ini.each { |i|
          case i
          when nil
          when String
            @mark << i.dup
          when Fixnum
            @mark << i
          when Array
            i.each { |j| @mark << j } # array of array is not incoming.
          end
        }
      end

      def getregion
        ret = @mark
        @mark = nil
        ret
      end

      def close
        @src.close # close input source
      end
    end ## of class In

    class StrIStream
      def initialize(src)
        @src = src
        @ix = 0
      end

      def to_s
        @src
      end

      def getc
        ch = @src[@ix]
        @ix += 1
        ch
      end

      def close
        @ix = 0
      end
    end ## of class StrIStream

    class TokenRegistry < ::Hash
      def [](key)
        super(::Symbol === key ? key : key.to_s.to_sym)
      end

      def []=(key, val)
        super(::Symbol === key ? key : key.to_s.to_sym, val.to_s)
      end

      def has_key?(key)
        super(::Symbol === key ? key : key.to_s.to_sym)
      end

      def delete(key)
        super(::Symbol === key ? key : key.to_s.to_sym)
      end

      def assoc(key)
        k_ = (::Symbol === key ? key : key.to_s.to_sym)
        self.has_key?(k_) ? [k_, self[k_]] : nil
      end
    end

    class CharRegistry
      def initialize(table_)
        @table = table_
      end

      def [](key)
        key = (::Integer === key) ? key.chr.to_sym : key.to_sym
        @table[key]
      end
    end

    # string derivative for IDL parsed identifiers able
    # to carry both 'raw' IDL name as well as language mapped
    # name
    class Identifier < DelegateClass(::String)
      attr_reader :checked_name, :unescaped_name

      def initialize(idl_id, checked_id, unescaped_idl_id = nil)
        super(idl_id)
        @checked_name = checked_id
        @unescaped_name = unescaped_idl_id || idl_id
      end
    end

    LFCR = [ ("\n"), ("\r") ]
    SPACES = [ ("\ "), ("\t") ]
    WHITESPACE = SPACES + LFCR

    ANNOTATION = '@'
    ANNOTATION_STR = '@'

    BREAKCHARS = [
      '(', ')', '[', ']', '{', '}',
      '^', '~',
      '*', '%', '&', '|',
      '<', '=', '>',
      ',', ';' ]

    SHIFTCHARS = [ '<', '>' ]

    DIGITS = ('0'..'9').to_a
    ALPHA_LC = ('a'..'z').to_a
    ALPHA_UC = ('A'..'Z').to_a
    OCTALS = ('0'..'7').to_a
    HEXCHARS = DIGITS + ('a'..'f').to_a + ('A'..'F').to_a
    SIGNS = ['-', '+']
    DOT = '.'

    IDCHARS = ['_' ] + ALPHA_LC + ALPHA_UC
    FULL_IDCHARS = IDCHARS + DIGITS

    ESCTBL = CharRegistry.new({
      n: "\n", t: "\t", v: "\v", b: "\b",
      r: "\r", f: "\f", a: "\a"
    })

    KEYWORDS = %w(
      abstract alias any attribute boolean case char component connector const consumes context custom default double
      exception emits enum eventtype factory FALSE finder fixed float getraises home import in inout interface local
      long manages mirrorport module multiple native Object octet oneway out port porttype primarykey private provides
      public publishes raises readonly setraises sequence short string struct supports switch TRUE truncatable typedef
      typeid typename typeprefix unsigned union uses ValueBase valuetype void wchar wstring
    ).inject(TokenRegistry.new) { |h, a| h[a.downcase.to_sym] = a
 h }

    LITERALS = [
      :integer_literal,
      :string_literal,
      # :wide_string_literal,
      :character_literal,
      # :wide_character_literal,
      :fixed_pt_literal,
      :floating_pt_literal,
      :boolean_literal]

    BOOL_LITERALS = {
        false: false,
        true: true
      }

    # Scanner
    def initialize(src, directiver, params = {})
      @includepaths = params[:includepaths] || []
      @xincludepaths = params[:xincludepaths] || []
      @idlversion = params[:idlversion]
      @stack = []
      @expansions = []
      @prefix = nil
      @directiver = directiver
      @directiver.instance_variable_get('@d').instance_variable_set('@scanner', self)
      @defined = TokenRegistry.new
      # initialize with predefined macros
      if params[:macros]
        params[:macros].each do |(name, value)|
          @defined[name] = value
        end
      end
      @ifdef = []
      @ifskip = false
      @ifnest = 0
      i = nil
      nm = ''
      case src
      when String
        i = StrIStream.new(src)
        nm = '<string>'
      when File
        i = src
        nm = src.path
      when IO, StringIO
        i = src
        nm = '<io>'
      else
        parse_error "illegal type for input source: #{src.class} "
      end
      @in = In.new(i, nm)
      @scan_comment = false # true if parsing commented annotation
      @in_annotation = false # true if parsing annotation

      # Extend the IDL keywords with IDL4 when enabled
      if @idlversion >= 4
        %w(bitfield bitmask bitset map int8 int16 int32 int64 uint8 uint16 uint32 uint64
    ).inject(KEYWORDS) { |h, a| h[a.downcase.to_sym] = a
h }
      end
    end

    def find_include(fname, all = true)
      if File.file?(fname) && File.readable?(fname)
        File.expand_path(fname)
      else
        # search transient include paths if allowed (quoted includes)
        fp = if all then
               @xincludepaths.find do |p|
                 check_include(p, fname)
               end
             else
               nil
             end
        # search system include paths if still needed
        fp = @includepaths.find do |p|
          check_include(p, fname)
        end unless fp
        fp += fname if fp
        fp
      end
    end

    def check_include(path, fname)
      fp = path + fname
      File.file?(fp) && File.readable?(fp)
    end

    def position
      @in.position
    end

    def enter_include(src, all = true)
      if @directiver.is_included?(src)
        @directiver.declare_include(src)
      else
        fpath = find_include(src, all)
        if fpath.nil?
          parse_error "Cannot open include file '#{src}'"
        end
        @stack << [:include, @prefix, @ifdef, @in, @ifskip]
        # record file dir as new searchpath
        @xincludepaths << (File.dirname(fpath) + '/')
        @prefix = nil
        @ifdef = []
        @in = In.new(File.open(fpath, 'r'), fpath)
        @directiver.enter_include(src, fpath)
        @directiver.pragma_prefix(nil)
      end
    end

    def enter_expansion(src, define)
      IDL.log(2, "** RIDL - enter_expansion > #{define} = #{src}")
      @stack << [:define, nil, nil, @in, nil]
      @expansions << define
      @in = In.new(StrIStream.new(src), @in.position.name, @in.position.line, @in.position.column)
    end

    def is_expanded?(define)
      @expansions.include?(define)
    end

    def more_source?
      !@stack.empty?
    end

    def in_expansion?
      more_source? and @stack.last[0] == :define
    end

    def leave_source
      # make sure to close the input source
      @in.close
      # check if we have any previous source still stacked up
      unless @stack.empty?
        if @stack.last[0] == :include
          @xincludepaths.pop # remove directory of finished include
          @directiver.leave_include
          _, @prefix, @ifdef, @in, @ifskip = @stack.pop
          @directiver.pragma_prefix(@prefix)
        else
          _, _, _, @in, _ = @stack.pop
          @expansions.pop
        end
      end
    end

    def do_parse?
      @ifdef.empty? || @ifdef.last
    end

    def positions
      @stack.reverse.inject(@in.nil? ? [] : [@in.position]) { |pos_arr, (_, _, _, in_, _)| pos_arr << in_.position }
    end

    def parse_error(msg, ex = nil)
      e = IDL::ParseError.new(msg, positions)
      e.set_backtrace(ex.backtrace) unless ex.nil?
      raise e
    end

    def is_literal?(o)
      LITERALS.include?(o)
    end

    def extract_annotation_value
      token = next_token # needs '{' (array) or literal or identifier (which means nested annotation object or enum value)
      if token.first == '{'
        # extract array of values (literals or identifiers) separated by ','
        annotation_value = []
        begin
          token, ann_value = extract_annotation_value
          parse_error 'invalid annotation value array' unless token.first == ',' || token.first == '}'
          annotation_value << ann_value
        end until token.first == '}'
        token = next_token
      elsif token.first == :identifier
        member_annotation_id = token.last.to_s
        # get nested body
        token, member_annotation_body = extract_annotation
        # determin vaue type; if it has a body it is an annotation instance
        annotation_value = if member_annotation_body
          { member_annotation_id => member_annotation_body }
        else # otherwise it is a symbolic value
          member_annotation_id.to_sym
        end
        # get next token if needed
        token = next_token unless token
      else
        parse_error 'invalid annotation member' unless is_literal?(token.first)
        annotation_value = token.last
        token = next_token
      end
      [token, annotation_value]
    end

    def extract_annotation
      annotation_body = nil
      # next token should be '(' in case of normal/single value annotation
      # or anything else in case of marker annotation
      skip_spaces # skip till next non-space or eol
      if peek_next == '('
        token = next_token # parse '('
        begin
          # identifier or value (in case of single value annotation) expected
          token = next_token
          if token.first == ')' # marker annotation; leave body empty
            annotation_body = { }
          else
            parse_error 'annotation member expected!' unless token.first == :identifier || is_literal?(token.first)
            s1 = token.last
            token = next_token # ')'  (in case of single value annotation) or '='
            if token.first == ')'
              parse_error 'invalid annotation member' if annotation_body
              annotation_body = { value: s1 }
            else
              parse_error 'invalid annotation member' unless token.first == '='
              token, annotation_value = extract_annotation_value
              parse_error 'invalid annotation body' unless token.first == ',' || token.first == ')'
              (annotation_body ||= {})[s1.to_s] = annotation_value
            end
          end
        end until token.first == ')'
        token = next_token_before_eol
      else
        token = next_token_before_eol
        # marker annotation or symbolic value; leave body nil
      end
      [token, annotation_body]
    end

    def parse_annotation(in_comment = false)
      @in_annotation = true
      @scan_comment = in_comment
      begin
        # parse (possibly multiple) annotation(s)
        begin
          annotation_position = self.position.dup
          # next token should be identifier (must be on same line following '@')
          token = next_token
          parse_error 'annotation identifier expected!' unless token.first == :identifier
          annotation_id = token.last.to_s
          token, annotation_body = extract_annotation
          # pass annotation to directiver for processing
          @directiver.define_annotation(annotation_id, annotation_position, in_comment, annotation_body || {})
        end until token.nil? || token.first != ANNOTATION_STR
      ensure
        @in_annotation = false
        @scan_comment = false
      end
      # check identifier for keywords
      if token&.first == :identifier
        # keyword check
        if (a = KEYWORDS.assoc(token.last.to_s)).nil?
          token = [:identifier, Identifier.new(token.last.to_s, chk_identifier(token.last.to_s), token.last.unescaped_name)]
        elsif token.last == a[1]
          token = [a[1], nil]
        else
          parse_error "'#{token.last}' collides with a keyword '#{a[1]}'"
        end
      end
      token
    end

    def peek_next
      @in.lookc
    end

    def skip_spaces
      @in.skipwhile { |c| SPACES.include?(c) }
    end

    def next_identifier(first = nil)
      @in.mark(first)
      while true
        if FULL_IDCHARS.include?(@in.lookc)
          @in.skipc
        else
          break
        end
      end
      s0 = @in.getregion        # raw IDL id
      s1 = s0.downcase.to_sym   # downcased symbolized
      s2 = s0.dup               # (to be) unescaped id

      # simple check
      if s2.empty?
        parse_error 'identifier expected!'
      else
        if s2[0] == '_'
          s2.slice!(0) ## if starts with CORBA IDL escape => remove
        end
        parse_error "identifier must begin with alphabet character: #{s2}" unless ALPHA_LC.include?(s2[0]) || ALPHA_UC.include?(s2[0])
      end

      # preprocessor check
      if @defined.has_key?(s2) and !is_expanded?(s2)
        # enter expansion as new source
        enter_expansion(@defined[s2], s2)
        # call next_token to parse expanded source
        next_token
      # keyword check
      elsif @in_annotation
        if BOOL_LITERALS.has_key?(s1)
          [:boolean_literal, BOOL_LITERALS[s1]]
        else
          [:identifier, Identifier.new(s2, s2, s0)]
        end
      elsif (a = KEYWORDS.assoc(s1)).nil?
        # check for language mapping keyword
        [:identifier, Identifier.new(s2, chk_identifier(s2), s0)]
      elsif s0 == a[1]
        [a[1], nil]
      else
        parse_error "'#{s0}' collides with IDL keyword '#{a[1]}'"
      end
    end

    def next_escape
      ret = 0
      case (ch = @in.getc)
      when nil
        parse_error 'illegal escape sequence'
      when '0'..'7'
        ret = ''
        ret << ch
        1.upto(2) {
          ch = @in.lookc
          if ('0'..'7').include? ch
            ret << ch
          else
            break
          end
          @in.skipc
        }
        ret = ret.oct
      when 'x' # i'm not sure '\x' should be 0 or 'x'. currently returns 0.
        ret = ''
        1.upto(2) {
          ch = @in.lookc
          if HEXCHARS.include? ch
            ret << ch
          else
            break
          end
          @in.skipc
        }
        ret = ret.hex
      when 'u'
        ret = ''
        1.upto(4) {
          ch = @in.lookc
          if HEXCHARS.include? ch
            ret << ch
          else
            break
          end
          @in.skipc
        }
        ret = ret.hex
      when 'n', 't', 'v', 'b', 'r', 'f', 'a'
        ret = ESCTBL[ch]
      else
        ret = ('' << ch).unpack('C').first
      end
      ret
    end

    def next_escape_str(keep_type_ch = false)
      ret = 0
      case (ch = @in.getc)
      when nil
        parse_error 'illegal escape sequence'
      when '0'..'7'
        ret = ''
        ret << ch
        1.upto(2) {
          ch = @in.lookc
          if ('0'..'7').include? ch
            ret << ch
          else
            break
          end
          @in.skipc
        }
        ret = [ :oct, ret ]
      when 'x' # i'm not sure '\x' should be 0 or 'x'. currently returns 0.
        ret = ''
        ret << ch if keep_type_ch
        1.upto(2) {
          ch = @in.lookc
          if HEXCHARS.include? ch
            ret << ch
          else
            break
          end
          @in.skipc
        }
        ret = [ :hex2, ret ]
      when 'u'
        ret = ''
        ret << ch if keep_type_ch
        1.upto(4) {
          ch = @in.lookc
          if HEXCHARS.include? ch
            ret << ch
          else
            break
          end
          @in.skipc
        }
        ret = [ :hex4, ret ]
      when 'n', 't', 'v', 'b', 'r', 'f', 'a'
        ret = ''
        ret << ch
        ret = [:esc, ret]
      else
        ret = ''
        ret << ch
        ret = [:esc_ch, ch]
      end
      ret
    end

    def skipfloat_or_fixed
      if @in.lookc == DOT
        @in.skipc
        @in.skipwhile { |c| DIGITS.include?(c) }
      end
      if ['e', 'E'].include? @in.lookc
        @in.skipc
        @in.skipc if SIGNS.include? @in.lookc
        @in.skipwhile { |c| DIGITS.include?(c) }
        return :floating_pt_literal
      elsif ['d', 'D'].include? @in.lookc
        @in.skipc
        @in.skipc if SIGNS.include? @in.lookc
        @in.skipwhile { |c| DIGITS.include?(c) }
        return :fixed_pt_literal
      end
      :floating_pt_literal
    end

    def skipline
      while true
        s = @in.gets
        until s.chomp!.nil?; end
        break unless s[s.length - 1] == "\\"
      end
    end

    def getline
      s = ''
      while true
        ch = @in.lookc
        break if ch.nil?

        case
        when (ch == "\"") # "
          s << @in.getc # opening quote
          while true
            if @in.lookc == "\\"
              # escape sequence
              s << @in.getc
              _, escstr = next_escape_str(true)
              s << escstr
            elsif @in.lookc == "\"" # "
              break
            elsif @in.lookc
              # normal character
              s << @in.getc
            else
              parse_error 'unterminated string literal'
            end
          end
          s << @in.getc # closing quote
        when (ch == "\'") # ' # quoted character
          s << @in.getc # opening quote
          if @in.lookc == "\\"
            # escape sequence
            s << @in.getc
            _, escstr = next_escape_str(true)
            s << escstr
          elsif @in.lookc && @in.lookc != "\'" # '
            # normal character
            s << @in.getc
          end
          if @in.lookc != "\'" # '
            parse_error "character literal must be single character enclosed in \"'\""
          end
          s << @in.getc # closing quote
        when LFCR.include?(ch)
          @in.skipwhile { |ch_| LFCR.include? ch_ }
          break
        when ch == '/'
          @in.skipc
          if @in.lookc == '/'
            # //-style comment; skip till eol
            @in.gets
            break
          elsif @in.lookc == '*'
            # /*...*/ style comment; skip comment
            ch1 = nil
            @in.skipuntil { |ch_|
              ch0 = ch1; ch1 = ch_
              ch0 == '*' and ch1 == '/' #
            }
            if @in.lookc.nil?
              parse_error "cannot find comment closing brace (\'*/\'). "
            end
            @in.skipc
          else
            s << ch
          end
        when ch == "\\"
          @in.skipc
          if LFCR.include?(@in.lookc)
            # line continuation
            @in.skipwhile { |ch_| LFCR.include? ch_ }
            if @in.lookc.nil?
              parse_error "line continuation character ('\\') not allowed as last character in file."
            end
          else
            s << ch
          end
        else
          @in.skipc
          s << ch
        end
      end
      s
    end

    def resolve_define(id, stack = [])
      return id if %w(true false).include?(id)

      IDL.log(3, "*** RIDL - resolve_define(#{id})")
      if @defined.has_key?(id)
        define_ = @defined[id]
        stack << id
        parse_error("circular macro reference detected for [#{define_}]") if stack.include?(define_)
        # resolve any nested macro definitions
        define_.gsub(/(^|[\W])([A-Za-z_][\w]*)/) do |_| "#{$1}#{resolve_define($2, stack)}" end
      else
        '0' # unknown id
      end
    end

    def eval_directive(s)
      IDL.log(3, "** RIDL - eval_directive(#{s})")
      rc = eval(s)
      case rc
      when FalseClass, TrueClass
        rc
      when Numeric
        rc != 0
      else
        parse_error 'invalid preprocessor expression.'
      end
    end

    def parse_directive
      @in.skipwhile { |c| SPACES.include?(c) }
      s = getline
      /^(\w*)\s*/ === s
      s1 = $1
      s2 = $' # '

      if /(else|endif|elif)/ === s1

        if @ifdef.empty?
          parse_error '#else/#elif/#endif must not appear without preceding #if'
        end
        case s1
        when 'else'
          if @ifnest.zero?
            if @ifskip # true branch has already been parsed
              @ifdef[@ifdef.size - 1] = false
            else
              @ifdef[@ifdef.size - 1] ^= true
              @ifskip = @ifdef.last
            end
          end
        when 'endif'
          if @ifnest.zero?
            @ifdef.pop
            @ifskip = @ifdef.last
          else
            @ifnest -= 1
          end
        else
          if @ifnest.zero?
            if @ifskip || @ifdef[@ifdef.size - 1]
              # true branch has already been parsed so skip from now on
              @ifdef[@ifdef.size - 1] = false
              @ifskip = true
            else
              while s2 =~ /(^|[\W])defined\s*\(\s*(\w+)\s*\)/
                 def_id = $2
                 s2.gsub!(/(^|[\W])(defined\s*\(\s*\w+\s*\))/, '\1' + "#{@defined.has_key?(def_id).to_s}")
              end
              s2.gsub!(/(^|[\W])([A-Za-z_][\w]*)/) do |_| "#{$1}#{resolve_define($2)}" end
              begin
                @ifdef[@ifdef.size - 1] = eval_directive(s2)
                @ifskip = @ifdef[@ifdef.size - 1]
              rescue IDL::ParseError
                raise
              rescue => e
                p e
                puts e.backtrace.join("\n")
                parse_error 'error evaluating #elif'
              end
            end
          end
        end

      elsif /(if|ifn?def)/ === s1

        if /ifn?def/ === s1
          if do_parse?
            parse_error 'no #if(n)def target.' unless /^(\w+)/ === s2
            @ifdef.push(@defined[$1].nil? ^ (s1 == 'ifdef'))
            @ifskip = @ifdef.last
          else
            @ifnest += 1
          end

        else # when 'if'
          if do_parse?
            # match 'defined(Foo)' or 'defined Foo'
            while s2 =~ /(^|[\W])defined(\s*\(\s*(\w+)\s*\)|\s+(\w+))/
              IDL.log(3, "** RIDL - parse_directive : resolving 'defined(#{$3 || $4})'")
              def_id = $3 || $4
              # resolve 'defined' expression to 'true' or 'false' according to actual macro definition
              s2.gsub!(/(^|[\W])(defined\s*[\s\(]\s*#{def_id}(\s*\))?)/, '\1' + "#{@defined.has_key?(def_id).to_s}")
            end
            # match and resolve any macro variables listed in conditional expression
            s2.gsub!(/(^|[\W])([A-Za-z_][\w]*)/) do |_| "#{$1}#{resolve_define($2)}" end
            begin
              @ifdef.push(eval_directive(s2))
              @ifskip = @ifdef.last
            rescue IDL::ParseError
              raise
            rescue => e
              p e
              puts e.backtrace.join("\n")
              parse_error 'error evaluating #if'
            end
          else
            @ifnest += 1
          end
        end

      elsif do_parse?

        case s1
        when 'pragma'
          parse_pragma(s2)

        when 'error'
          parse_error(s2)

        when 'define'
          defid = s2.split.first
          parse_error 'no #define target.' unless defid
          parse_error "#{defid} is already #define-d." if @defined[defid]
          defval = s2.sub(/^\s*#{defid}/, '').strip
          defval = true if defval.empty?
          @defined[defid] = defval

        when 'undef'
          @defined.delete(s2)

        when 'include'
          if s2[0, 1] == '"' || s2[0, 1] == '<'
            quoted_inc = (s2[0, 1] == '"')
            if s2.size > 2
              s2.strip!
              s2 = s2.slice(1..(s2.size - 2))
            else
              s2 = ''
            end
          end
          enter_include(s2, quoted_inc)

        when /[0-9]+/
          # ignore line directive
        else
          parse_error "unknown directive: #{s}."
        end
      end
    end

    def parse_pragma(s)
      case s
      when /^ID\s+(.*)\s+"(.*)"\s*$/
        @directiver.pragma_id($1.strip, $2)
      when /^version\s+(.*)\s+([0-9]+)\.([0-9]+)\s*$/
        @directiver.pragma_version($1.strip, $2, $3)
      when /^prefix\s+"(.*)"\s*$/
        @prefix = $1
        @directiver.pragma_prefix(@prefix)
      else
        @directiver.handle_pragma(s)
      end
    end

    def next_token_before_eol
      @in.skipwhile { |c| SPACES.include?(c) }
      LFCR.include?(@in.lookc) ? nil : next_token
    end

    def next_token
      sign = nil
      str = '' # initialize empty string
      while true
        ch = @in.getc
        if ch.nil?
          if !@ifdef.empty? and !in_expansion?
            parse_error 'mismatched #if/#endif'
          end
          if more_source?
            leave_source
            next
          else
            return [false, nil]
          end
        end

        if WHITESPACE.include? ch
          @in.skipwhile { |c| WHITESPACE.include?(c) }
          next
        end

        if str.empty? && ch == "\#"
          parse_directive
          next
        end
        unless do_parse?
          skipline
          next
        end

        str << ch
        case
        when BREAKCHARS.include?(ch)
          if SHIFTCHARS.include?(ch) && @in.lookc == ch
            # '<<' or '>>'
            str << @in.getc
          end
          return [str, str]

        when ch == ANNOTATION
          if @in_annotation
            return [str, str]
          else
            # return token returned by parse_annotation or parse next token recursively
            return parse_annotation || next_token
          end

        when ch == ':' #
          if @in.lookc == ':' #
            @in.skipc
            return %w(:: ::)
          else
            return %w(: :)
          end

        when ch == 'L'
          _nxtc = @in.lookc
          if _nxtc == "\'" # ' #single quote, for a character literal.
            @in.skipc # skip 'L'
            _nxtc = @in.lookc
            ret = if _nxtc == "\\"
              @in.skipc
              next_escape_str
            elsif _nxtc == "\'" # '
              [ nil, nil ]
            else
              [:char, '' << @in.getc]
            end

            if @in.lookc != "\'" # '
              parse_error "wide character literal must be single wide character enclosed in \"'\""
            end

            @in.skipc
            return [:wide_character_literal, ret]

          elsif _nxtc == "\"" # " #double quote, for a string literal.
            ret = []
            chs = ''
            @in.skipc # skip 'L'
            while true
              _nxtc = @in.lookc
              if _nxtc == "\\"
                @in.skipc
                ret << [:char, chs] unless chs.empty?
                chs = ''
                ret << next_escape_str
              elsif _nxtc == "\"" # "
                @in.skipc
                ret << [:char, chs] unless chs.empty?
                return [:wide_string_literal, ret]
              else
                chs << @in.getc
              end
            end

          else
            return next_identifier(ch)
          end

        when IDCHARS.include?(ch)
          return next_identifier(ch)

        when ch == '/' #
          _nxtc = @in.lookc
          if _nxtc == '*'
            # skip comment like a `/* ... */'
            @in.skipc # forward stream beyond `/*'
            ch1 = nil
            @in.skipuntil { |ch_|
              ch0 = ch1; ch1 = ch_
              ch0 == '*' and ch1 == '/' #
            }
            if @in.lookc.nil?
              parse_error "cannot find comment closing brace (\'*/\'). "
            end
            @in.skipc
            str = '' # reset
            next

          elsif _nxtc == '/'
            # skip comment like a `// ...\n'
            @in.skipc
            unless @scan_comment # scan_comment will be true when parsing commented annotations
              _nxtc = @in.lookc
              if _nxtc == ANNOTATION
                @in.skipc
                # return token returned by parse_annotation or parse next token recursively
                return parse_annotation(true) || next_token
              else
                @in.skipuntil { |c| LFCR.include?(c) }
              end
            end
            str = '' # reset
            next

          else
            return %w(/ /)
          end

        when SIGNS.include?(ch)
          _nxtc = @in.lookc
          if DIGITS.include? _nxtc
            sign = ch
            str = '' # reset
            next
          else
            return [str, str]
          end

        when ('1'..'9').include?(ch)
          @in.mark(sign, ch)
          @in.skipwhile { |c| DIGITS.include?(c) }
          num_type = (['.', 'e', 'E', 'd', 'D'].include?(@in.lookc)) ? skipfloat_or_fixed : :integer_literal

          r = @in.getregion

          if num_type == :floating_pt_literal
            return [:floating_pt_literal, r.to_f]
          elsif num_type == :fixed_pt_literal
            return [:fixed_pt_literal, r]
          else
            return [:integer_literal, r.to_i]
          end

        when ch == DOT #
          @in.mark(ch)
          @in.skipwhile { |c| DIGITS.include?(c) }
          num_type = (DOT != @in.lookc) ? skipfloat_or_fixed : nil
          s = @in.getregion
          if s == '.'
            parse_error 'token consisting of single dot (.) is invalid.'
          end
          if num_type == :floating_pt_literal
            return [:floating_pt_literal, s.to_f]
          elsif num_type == :fixed_pt_literal
            return [:fixed_pt_literal, s]
          else
            parse_error 'invalid floating point constant.'
          end

        when ch == '0'
          @in.mark(sign, ch)

          _nxtc = @in.lookc
          if _nxtc == 'x' || _nxtc == 'X'
            @in.skipc
            @in.skipwhile { |ch_| HEXCHARS.include? ch_ }
            s = @in.getregion
            return [:integer_literal, s.hex]
          else
            dec = false
            @in.skipwhile { |c| OCTALS.include?(c) }
            if ('8'..'9').include? @in.lookc
              dec = TRUE
              @in.skipwhile { |c| DIGITS.include?(c) }
            end

            num_type = (['.', 'e', 'E', 'd', 'D'].include?(@in.lookc)) ? skipfloat_or_fixed : :integer_literal

            s = @in.getregion
            ret = if num_type == :floating_pt_literal
              [:floating_pt_literal, s.to_f]
            elsif num_type == :fixed_pt_literal
              [:fixed_pt_literal, s]
            elsif dec
              parse_error "decimal literal starting with '0' should be octal ('0'..'7' only): #{s}"
            else
              [:integer_literal, s.oct]
            end
            return ret
          end

        when ch == "\'" # ' #single quote, for a character literal.
          _nxtc = @in.lookc
          ret = if _nxtc == "\\"
            @in.skipc
            next_escape
          elsif _nxtc == "\'" # '
            0
          elsif _nxtc
            ('' << @in.getc).unpack('C').first
          end

          if @in.lookc != "\'" # '
            parse_error "character literal must be single character enclosed in \"'\""
          end

          @in.skipc
          return [:character_literal, ret]

        when ch == "\"" # " #double quote, for a string literal.
          ret = ''
          while true
            _nxtc = @in.lookc
            if _nxtc == "\\"
              @in.skipc
              ret << next_escape
            elsif _nxtc == "\"" # "
              @in.skipc
              return [:string_literal, ret]
            elsif _nxtc
              ret << @in.getc
            else
              parse_error 'unterminated string literal'
            end
          end

        else
          parse_error 'illegal character [' << ch << ']'

        end # of case

      end # of while
      parse_error 'unexcepted error'
    end # of method next_token
  end
end
