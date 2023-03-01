#--------------------------------------------------------------------
# genfile.rb - Generator file class implementation.
#
# Author: Martin Corino
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the RIDL LICENSE which is
# included with this program.
#
# Copyright (c) Remedy IT Expertise BV
#--------------------------------------------------------------------
require 'tempfile'
require 'fileutils'

module IDL
  class GenFile

    self.singleton_class.class_eval do
      private

      def _stack
        @stack ||= []
      end

      def _start_transaction
        _stack << (@transaction = [])
      end

      def _close_transaction
        _stack.pop
        @transaction = _stack.last
      end

      def _transaction
        @transaction
      end

      def _commit
        _transaction.reject! { |fgen| fgen.save; true }
      end

      def _rollback
        _transaction.reject! { |fgen| fgen.remove; true } if _transaction
      end

      def _push(fgen)
        _transaction << fgen if _transaction
      end

    end
    def self.transaction(&block)
      _start_transaction
      begin
        block.call if block_given?
        _commit
      ensure
        _rollback # after successful transaction should be nothing left
        _close_transaction
      end
    end

    def self.rollback
      _rollback
    end

    class Content
      def initialize(sections = {})
        # copy content map transforming all keys to symbols
        @sections = sections.inject({}) { |m, (k, v)| m[k.to_sym] = v; m }
      end

      def sections
        @sections.keys
      end

      def has_section?(sectionid)
        @sections.has_key?((sectionid || '').to_sym)
      end

      def [](sectionid)
        @sections[(sectionid || '').to_sym]
      end

      def each(&block)
        @sections.each(&block)
      end
    end

    REGEN_MARKER_DEFAULT = '@@{__RIDL_REGEN_MARKER__}'

    attr_reader :path, :fullpath, :name, :ext, :content

    def initialize(path, opts = {})
      if path
        @path = path
        @fullpath = File.expand_path(path)
        @name = File.basename(path)
        @ext = File.extname(path).sub(/^\./, '')
      else
        @path = @fullpath = @name = @ext = ''
      end
      @options = {
        regenerate: false,
        regen_marker_prefix: '//',
        regen_marker_postfix: nil,
        regen_marker: REGEN_MARKER_DEFAULT,
        regen_keep_header: true,
        output_file: nil,
        create_missing_dir: false
      }.merge(opts)
      if @options[:regenerate] && File.exist?(@fullpath)
        parse_regeneration_content
      else
        @content = Content.new
      end
      @fout = @options[:output_file] || Tempfile.new(@name)
      self.class.__send__(:_push, self)
    end

    def <<(txt)
      @fout << txt if @fout
      self
    end

    def regen_start_marker(sectionid)
      "#{@options[:regen_marker_prefix]}#{@options[:regen_marker]} - BEGIN : #{sectionid}#{@options[:regen_marker_postfix]}"
    end

    def regen_end_marker(sectionid)
      "#{@options[:regen_marker_prefix]}#{@options[:regen_marker]} - END : #{sectionid}#{@options[:regen_marker_postfix]}"
    end

    def regen_header_end_marker(sectionid)
      "#{@options[:regen_marker_prefix]}#{@options[:regen_marker]} - HEADER_END : #{sectionid}#{@options[:regen_marker_postfix]}"
    end

    def write_regen_section(sectionid, options = {})
      indent = options[:indent] || ''
      self << indent << regen_start_marker(sectionid) << "\n" unless options[:header]
      if content.has_section?(sectionid)
        self << content[sectionid].join unless content[sectionid].empty?
      elsif block_given?
        yield # block should yield default content
      elsif default_content = options[:default_content]
        default_content = (Array === default_content) ? default_content : default_content.to_s.split("\n")
        self << (default_content.collect { |l| (s = indent.dup) << l << "\n"; s }.join) unless default_content.empty?
      end
      if options[:header]
        self << indent << regen_header_end_marker(sectionid) << "\n"
      else
        self << indent << regen_end_marker(sectionid) << "\n" unless options[:footer]
      end
    end

    def save
      return if @options[:output_file]

      if @fout
        fgen = @fout
        @fout = nil
        fgen.close(false) # close but do NOT unlink
        if File.exist?(@fullpath)
          # create temporary backup
          ftmp = Tempfile.new(@name)
          ftmp_name = ftmp.path.dup
          ftmp.close(true) # close AND unlink
          FileUtils::mv(@fullpath, ftmp_name) # backup existing file
          # replace original
          begin
            # rename newly generated file
            FileUtils.mv(fgen.path, @fullpath)
            # preserve file mode
            FileUtils.chmod(File.lstat(ftmp_name).mode, @fullpath)
          rescue
            IDL.log(0, %Q{ERROR: FAILED updating #{@path}: #{$!}})
            # restore backup
            FileUtils.mv(ftmp_name, @fullpath)
            raise
          end
          # remove backup
          File.unlink(ftmp_name)
        else
          unless File.directory?(File.dirname(@fullpath))
            unless @options[:create_missing_dir]
              IDL.log(0, %Q{ERROR: Cannot access output folder #{File.dirname(@fullpath)}})
              exit(1)
            end
            FileUtils.mkdir_p(File.dirname(@fullpath))
          end
          # just rename newly generated file
          FileUtils.mv(fgen.path, @fullpath)
          # set default mode for new files
          FileUtils.chmod(0666 - File.umask, @fullpath)
        end
      end
    end

    def remove
      return if @options[:output_file]

      if @fout
        begin
          @fout.close(true)
        rescue
          IDL.log(0, %Q{ERROR: FAILED to clean up temp file #{@fout.path}: #{$!}})
        end
        @fout = nil
      end
    end

  private

    def parse_regeneration_content
      markers_sel = %w{BEGIN END}
      _keep_header = (@options[:regen_keep_header] == true)
      markers_sel << 'HEADER_END' if _keep_header
      regen_marker_re = /#{@options[:regen_marker]}\s+[-]\s+(#{markers_sel.join('|')})\s+:\s+(.+)/
      sections = {}
      section = []
      in_section = _keep_header ? ['HEADER', 0] : nil
      linenr = 0
      File.open(@fullpath) do |fio|
        fio.each do |line|
          linenr += 1
          if regen_marker_re =~ line
            case $1
            when 'BEGIN'
              raise "ERROR: Found unterminated regeneration section starting at #{@path}:#{in_section.last}." if in_section

              in_section = [$2, linenr]
              section = []
            when 'END'
              raise "ERROR: Found unmatched regeneration end at #{@path}:#{linenr}." unless in_section && ($2 == in_section.first)

              sections[$2] = section
              in_section = nil
              section = []
            when 'HEADER_END'
              raise "ERROR: Found illegal header end marker at #{@path}:#{linenr}." unless _keep_header && in_section &&
                                                                                                         ('HEADER' == in_section.first ) && (0 == in_section.last)

              sections[$2] = section
              in_section = nil
              section = []
            else
              raise "ERROR: Found invalid regeneration marker at #{@path}:#{linenr}."
            end
          elsif in_section
            section << line
          end
        end
      end
      sections[in_section.first] = section if in_section
      @content = Content.new(sections)
    end

  end
end
