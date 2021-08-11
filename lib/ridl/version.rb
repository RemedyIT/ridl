#--------------------------------------------------------------------
# version.rb - Version file for Ruby IDL compiler
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

  RIDL_VERSION_MAJOR = 2
  RIDL_VERSION_MINOR = 8
  RIDL_VERSION_RELEASE = 1
  RIDL_VERSION = "#{RIDL_VERSION_MAJOR}.#{RIDL_VERSION_MINOR}.#{RIDL_VERSION_RELEASE}"
  RIDL_COPYRIGHT = "Copyright (c) 2007-#{Time.now.year} Remedy IT Expertise BV, The Netherlands".freeze

end
