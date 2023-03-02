#--------------------------------------------------------------------
# require.rb - IDL language mapping loader
#
# Author: Martin Corino
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the RIDL LICENSE which is
# included with this program.
#
# Copyright (c) Remedy IT Expertise BV
#--------------------------------------------------------------------
# frozen_string_literal: true

(Dir.glob(File.join(File.dirname(__FILE__), '*.rb')) - [__FILE__]).each do |f|
  require f
end
