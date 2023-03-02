#--------------------------------------------------------------------
# run.rb - Standalone Ruby IDL compiler runner
#
# Author: Martin Corino
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the RIDL LICENSE which is
# included with this program.
#
# Copyright (c) Remedy IT Expertise BV
#--------------------------------------------------------------------
require 'stringio'
require 'ridl/optparse_ext'
require 'ridl/genfile'
require 'ridl/backend'
require 'ridl/options'

# -----------------------------------------------------------------------

module IDL
  OPTIONS = Options.new({
      outputdir: nil,
      includepaths: [],
      xincludepaths: [],
      verbose: (ENV['RIDL_VERBOSE'] || 0).to_i,
      debug: false,
      namespace: nil,
      search_incpath: false,
      backend: nil,
      macros: {
      }
  })
  CORE_OPTIONS = OPTIONS.keys

  class Engine
    class ProductionStack
      def initialize
        @stack = []
        @index = {}
      end

      def size
        @stack.size
      end

      def empty?
        @stack.empty?
      end

      def push(id, prod)
        @index[id.to_sym] = @stack.size
        @stack << [id.to_sym, prod]
      end

      def pop
        return nil if empty?

        id, prod = @stack.shift
        @index.delete(id)
        prod
      end

      def peek
        return nil if empty?

        id, _ = @stack.first
        id
      end

      def remove(id)
        return nil unless has?(id)

        i = @index.delete(id.to_sym)
        _, producer = @productionstack.delete(i)
        producer
      end

      def has?(id)
        @index.has_key?(id.to_sym)
      end

      def [](id)
        @stack[@index[id.to_sym]].last
      end
    end

    def initialize(backend, options)
      @backend = backend ? Backend.load(backend) : Backend.null_be
      @initopts = options.merge({
        backend: @backend.name,
        macros: options[:macros].merge({
           __RIDL__: "#{RIDL_VERSION}",
           __RIDLBE__: @backend.name.to_s,
           __RIDLBE_VER__: @backend.version
        })
      })
      @optparser = init_optparser
      @inputstack = []
      @productionstack = ProductionStack.new
      @options = nil
    end

    def backend
      @backend
    end

    def options
      @options || @initopts
    end

    # Input management

    def push_input(idlfile, opts)
      @inputstack << [idlfile, opts]
    end

    def pop_input
      @inputstack.shift
    end

    def peek_input
      @inputstack.first
    end

    def has_input?
      !@inputstack.empty?
    end

    # Production management

    def push_production(id, producer)
      raise "Producer #{id} already queued" if @productionstack.has?(id)

      @productionstack.push(id, producer)
    end

    def pop_production
      @productionstack.pop
    end

    def peek_production
      @productionstack.peek
    end

    def remove_production(id)
      @productionstack.remove(id)
    end

    def has_productions?
      !@productionstack.empty?
    end

    def has_production?(id)
      @productionstack.has?(id)
    end

    def production(id)
      @productionstack[id]
    end

    # Verbosity control

    def verbose_level
      options[:verbose]
    end

    def verbose_level=(l)
      options[:verbose] = l
    end

    def run(argv, runopts = {})

      # initialize options
      @options = @initopts.merge(runopts)

      # mark current (clean) state
      @options.mark

      # backup current engine (if any)
      cur_engine = Thread.current[:ridl_engine]
      # store currently running engine for current thread
      Thread.current[:ridl_engine] = self

      begin
        # parse arguments
        begin
          @optparser.parse!(argv)
        rescue ArgumentError => e
          IDL.error(e.inspect)
          IDL.error(e.backtrace.join("\n")) if IDL.verbose_level.positive?
          return false
        end

        if options[:preprocess]

          ## PREPROCESSING
          o = if options[:output].nil?
                $stdout
              else
                File.open(options[:output], 'w+')
              end
          options[:output] = o

          input_base = File.basename(argv.first)
          if input_base != argv.first
            options[:xincludepaths] << (File.dirname(argv.first) + '/')
          end

          return !parse("#include \"#{input_base}\"", options).nil?
        else
          ## collect input files from commandline
          collect_input(argv)

          ## CODE GENERATION
          while has_input?
            # get input from stack
            _idlfile, _opts = pop_input

            _fio = if IO === _idlfile || StringIO === _idlfile
                     _idlfile
                   else
                     File.open(_idlfile, 'r')
                   end
            raise 'cannot read from STDOUT' if $stdout == _fio

            # parse IDL source
            IDL.log(1, "RIDL - parsing #{IO === _idlfile ? 'from STDIN' : (StringIO === _idlfile ? 'from string' : _idlfile)}")

            unless _parser = parse(_fio, _opts)
              return false
            end

            # process parse result -> code generation
            IDL.log(2, 'RIDL - processing input')

            GenFile.transaction do
              begin

                backend.process_input(_parser, _opts)

                # handle productions
                while has_productions?
                  IDL.log(2, "RIDL - running production #{peek_production}")

                  # get next-in-line producer
                  producer = pop_production

                  # execute the producer
                  producer.run(_parser)
                end

              rescue Backend::ProcessStop
                IDL.log(2, "RIDL - processing #{IO === _idlfile ? 'from STDIN' : (StringIO === _idlfile ? 'from string' : _idlfile)} stopped with \"#{$!.message}\"")

              rescue => e
                IDL.error(e)
                IDL.error(e.backtrace.join("\n")) unless e.is_a? IDL::ParseError
                return false
              end
            end
          end
        end
      ensure
        # restore previous state
        Thread.current[:ridl_engine] = cur_engine
      end
      true
    end

    def parse(io, opts)
      # parse IDL source
      _parser = ::IDL::Parser.new(opts)
      _parser.yydebug = opts[:debug]

      begin
        _parser.parse(io)
      rescue => e
        IDL.error(e.inspect)
        IDL.error(e.backtrace.join("\n")) unless e.is_a? IDL::ParseError
        return nil
      ensure
        io.close unless String === io || io == $stdin
      end
      _parser
    end

    private

    def collect_input(argv)
      ## collect input files from commandline
      argv.each do |_arg|
        _opts = options.dup

        _opts[:idlfile] = _arg
        if _opts[:no_input]
          # do not parse specified file (only used as template for output names)
          # instead push an empty StringIO object
          _arg = StringIO.new('')
        else
          if _opts[:search_incpath]
            _fname = _arg
            _fpath = if File.file?(_fname) && File.readable?(_fname)
                       _fname
                     else
                       _fp = _opts[:includepaths].find do |_p|
                         _f = _p + _fname
                         File.file?(_f) && File.readable?(_f)
                       end
                       _opts[:outputdir] = _fp unless _fp.nil? || !_opts[:outputdir].nil?
                       _fp += '/' + _fname unless _fp.nil?
                       _fp
                     end
            _arg = _fpath unless _fpath.nil?
          end
          _opts[:xincludepaths] << (File.dirname(_arg) + '/')
        end

        _opts[:outputdir] ||= '.'

        push_input(_arg, _opts)
      end

      ## if no IDL input file specified read from STDIN
      unless has_input?
        _opts = options.dup
        _opts[:outputdir] ||= '.'
        push_input($stdin, _opts)
      end
    end

    def init_optparser
      script_name = File.basename($0, '.*')
      unless script_name =~ /ridlc/
        script_name = 'ruby ' + $0
      end

      # set up option parser with common options
      opts = OptionParser.new
      opts.banner = "Usage: #{script_name} [:backend] [options] [<idlfile> [<idlfile> ...]]\n\n" +
          "    backend\t\tSpecifies the IDL language mapping backend to use.\n" +
          "           \t\tDefault = :null\n\n" +
          "    Active language mapping = :#{backend.name}"
      opts.separator ''
      opts.on('-I PATH', '--include=PATH', String,
              'Adds include searchpath.',
              'Default: none') { |v|
        self.options[:includepaths] << (v.end_with?('\\', '/') ? v : v + '/')
      }
      opts.on('-Dmacro=[value]', String, 'defines preprocessor macro') { |v|
        name, value = v.split('=')
        self.options[:macros][name] = (value ? value : true)
      }
      opts.on('-n NAMESPACE', '--namespace=NAMESPACE', String,
              'Defines rootlevel enclosing namespace.',
              'Default: nil') { |v|
        self.options[:namespace] = v
      }
      opts.on('-v', '--verbose',
              'Set verbosity level. Repeat to increment.',
              'Default: 0') { |_|
        self.options[:verbose] += 1
      }
      opts.on('--debug',
              'Set parser debug mode. Do NOT do this at home!',
              'Default: off') { |_|
        self.options[:debug] = true
      }
      opts.on('--search-includepath',
              'Use include paths to find main IDL source.',
              'Default: off') { |_|
        self.options[:search_incpath] = true
      }
      opts.on('--no-input',
               'Do not parse specified file(s) as input IDL.',
               'Default: off') { |_|
        self.options[:no_input] = true
      }
      if @initopts[:preprocess]
        opts.on('--output=FILE', String,
                'Specifies filename to generate output in.',
                'Default: basename(idlfile)-\'.idl\'+<postfix>+<ext>') { |v|
          self.options[:output] = v
        }
      end

      # setup language mapping specific options
      be_options = OptionList.new
      @backend.setup_be(be_options, @initopts)
      be_options.to_option_parser(opts, self)

      opts.on('-V', '--version',
              'Show version information and exit.') {
        puts "RIDL compiler #{RIDL_VERSION}"
        puts RIDL_COPYRIGHT
        puts '---'
        @backend.print_version
        exit
      }

      opts.separator ""

      opts.on('-h', '--help',
              'Show this help message.') { puts opts
 puts
 exit }

      opts
    end
  end

  def IDL.engine?
    !Thread.current[:ridl_engine].nil?
  end

  def IDL.backend
    Thread.current[:ridl_engine] ? Thread.current[:ridl_engine].backend : nil
  end

  def IDL.push_input(idlfile, opts)
    Thread.current[:ridl_engine].push_input(idlfile, opts) if engine?
  end

  def IDL.pop_input
    return nil unless engine?

    Thread.current[:ridl_engine].pop_input
  end

  def IDL.peek_input
    return nil unless engine?

    Thread.current[:ridl_engine].peek_input
  end

  def IDL.has_input?
    engine? && Thread.current[:ridl_engine].has_input?
  end

  def IDL.push_production(id, producer)
    Thread.current[:ridl_engine].push_production(id, producer) if engine?
  end

  def IDL.pop_production
    return nil unless engine?

    Thread.current[:ridl_engine].pop_production
  end

  def IDL.remove_production(id)
    return nil unless engine?

    Thread.current[:ridl_engine].remove_production(id)
  end

  def IDL.has_productions?
    engine? && Thread.current[:ridl_engine].has_productions?
  end

  def IDL.has_production?(id)
    engine? && Thread.current[:ridl_engine].has_production?(id)
  end

  def IDL.production(id)
    return nil unless engine?

    Thread.current[:ridl_engine].production(id)
  end

  def IDL.verbose_level
    Thread.current[:ridl_engine] ? Thread.current[:ridl_engine].verbose_level : OPTIONS[:verbose]
  end

  def IDL.verbose_level=(l)
    if Thread.current[:ridl_engine]
      Thread.current[:ridl_engine].verbose_level = l.to_i
    else
      OPTIONS[:verbose] = l.to_i
    end
  end

  def IDL.log(level, message)
    STDERR.puts message if verbose_level >= level
  end

  def IDL.error(message)
    STDERR.puts(message)
  end

  def IDL.fatal(message)
    STDERR.puts(message, 'Exiting.')
    exit 1
  end

  def IDL.init(argv = ARGV)
    options = OPTIONS.dup

    # load config file(s) if any
    Options.load_config(options)

    IDL.log(2, "Configuration [#{options}]")

    # check commandline args for explicit language mapping backend
    if argv.first =~ /^:\S+/
      be_name = argv.shift.reverse.chop.reverse.to_sym
    elsif ENV['RIDL_BE_SELECT']   # or from environment
      be_name = ENV['RIDL_BE_SELECT'].to_sym
    elsif options[:backend]       # or from configuration
      be_name = options[:backend].to_sym
    end

    # add optional search paths for RIDL backends
    options[:be_path] ||= []
    options[:be_path].unshift(*ENV['RIDL_BE_PATH'].split(/#{File::PATH_SEPARATOR}/)) if ENV['RIDL_BE_PATH']
    options[:be_path].collect! { |p| p.gsub('\\', '/') } # cleanup to prevent mixed path separators
    $:.concat(options[:be_path]) unless options[:be_path].empty?

    # check for special bootstrapping switches
    if argv.first == '--preprocess'
      options[:preprocess] = true
      argv.shift
    elsif argv.first == '--ignore-pidl'
      options[:ignore_pidl] = true
      argv.shift
    end

    # create RIDL engine
    Thread.current[:ridl_engine] = Engine.new(be_name, options)
  end

  # main run method
  #
  def IDL.run(argv = ARGV)
    # run default engine if available
    if Thread.current[:ridl_engine]
      exit(1) unless Thread.current[:ridl_engine].run(argv)
    end
  end # IDL.run
end
