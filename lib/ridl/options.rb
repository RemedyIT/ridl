#--------------------------------------------------------------------
# options.rb - Ruby IDL compiler options class
#
# Author: Martin Corino
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the RIDL LICENSE which is
# included with this program.
#
# Copyright (c) Remedy IT Expertise BV
#--------------------------------------------------------------------

require 'ostruct'
require 'json'

module IDL

  RIDLRC = '.ridlrc'
  RIDLRC_GLOBAL = File.expand_path(File.join(ENV['HOME'] || ENV['HOMEPATH'] || '~', RIDLRC))

  class Options < OpenStruct

    def initialize(hash=nil, marked=nil)
      super(hash)
      @marked = marked
    end

    def merge!(from, *keys)
      _merge(@table, from, *keys)
      self
    end

    def merge(from, *keys)
      self.dup.merge!(from, *keys)
    end

    def copy!(from, *keys)
      keys.flatten.each {|k| self[k] = from[k] }
      self
    end

    def copy(from, *keys)
      self.dup.copy!(from, *keys)
    end

    def delete(k)
      modifiable.delete(k)
    end

    def has_key?(k)
      @table.has_key?(k)
    end

    def keys
      @table.keys
    end

    def dup
      self.class.new(_dup_elem(@table), @marked)
    end

    def mark
      @marked = _dup_elem(@table)
    end

    def restore
      self.class.new(_dup_elem(@marked || @table), @marked)
    end


    def load(rcpath)
      IDL.log(3, "Loading #{RIDLRC} from #{rcpath}")
      _cfg = JSON.parse(IO.read(rcpath))
      IDL.log(4, "Read from #{rcpath}: [#{_cfg}]")
      _rcdir = File.dirname(rcpath)
      # handle automatic env var expansion in ridl be_paths
      _cfg['be_path'] = (_cfg['be_path'] || []).collect do |p|
        IDL.log(5, "Examining RIDL be path [#{p}]")
        # for paths coming from rc files environment vars are immediately expanded and
        p.gsub!(/\$([^\s\/]+)/) { |m| ENV[$1] }
        IDL.log(6, "Expanded RIDL be path [#{p}]")
        # resulting relative paths converted to absolute paths
        _fp = File.expand_path(p, _rcdir)
        if File.directory?(_fp) # relative to rc location?
          p = _fp
        end # or relative to working dir
        IDL.fatal("Cannot access RIDL backend search path #{p} configured in #{rcpath}") unless File.directory?(p)
        IDL.log(4, "Adding RIDL backend search path : #{p}")
        p
      end
      merge!(_cfg)
    end

    protected

    def _merge(to, from, *keys)
      keys = keys.flatten.collect {|k| k.to_sym}
      keys = from.keys if keys.empty?
      keys.each do |k|
        if from.has_key?(k)
          v = from[k]
          k = k.to_sym
          if to.has_key?(k)
            case to[k]
            when Array
              to[k].concat v
            when Hash
              to[k].merge!(Hash === v ? v : v.to_h)
            when OpenStruct
              _merge(to[k].__send__(:table), v)
            else
              to[k] = v
            end
          else
            to[k] = v
          end
        end
      end
      to
    end

    def _dup_elem(v)
      case v
      when Array
        v.collect {|e| _dup_elem(e) }
      when Hash
        v.inject({}) {|h, (k,e)| h[k] = _dup_elem(e); h }
      when OpenStruct
        v.class.new(_dup_elem(v.__send__(:table)))
      else
        v
      end
    end

    public

    def self.load_config(opt)
      # first collect config from known (standard and configured) locations
      _rc_paths = [ RIDLRC_GLOBAL ]
      _loaded_rc_paths = []
      (ENV['RIDLRC'] || '').split(/:|;/).each do |p|
        _rc_paths << p unless _rc_paths.include?(p)
      end
      _rc_paths.collect {|path| File.expand_path(path) }.each do |rcp|
        IDL.log(3, "Testing rc path #{rcp}")
        if File.readable?(rcp) && !_loaded_rc_paths.include?(rcp)
          opt.load(rcp)
          _loaded_rc_paths << rcp
        else
          IDL.log(3, "Ignoring #{File.readable?(rcp) ? 'already loaded' : 'inaccessible'} rc path #{rcp}")
        end
      end
      # now scan working path for any rc files
      _cwd = File.expand_path(Dir.getwd)
      IDL.log(3, "scanning working path #{_cwd} for rc files")
      # first collect any rc files found
      _rc_paths = []
      begin
        _rcp = File.join(_cwd, RIDLRC)
        if File.readable?(_rcp) && !_loaded_rc_paths.include?(_rcp)
          _rc_paths << _rcp unless _rc_paths.include?(_rcp)
        else
          IDL.log(3, "Ignoring #{File.readable?(_rcp) ? 'already loaded' : 'inaccessible'} rc path #{_rcp}")
        end
        break if /\A(.:(\\|\/)|\.|\/)\Z/ =~ _cwd
        _cwd = File.dirname(_cwd)
      end while true
      # now load them in reverse order
      _rc_paths.reverse.each do |_rcp|
        opt.load(_rcp)
        _loaded_rc_paths << _rcp
      end
    end
  end

end
