#--------------------------------------------------------------------
# help.rake - build file
#
# Author: Martin Corino
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the RIDL LICENSE which is
# included with this program.
#
# Copyright (c) Remedy IT Expertise BV
# Chamber of commerce Rotterdam nr.276339, The Netherlands
#--------------------------------------------------------------------

module RIDL
  HELP = <<__HELP_TXT

RIDL Rake based build system
-------------------------------

commands:

rake [rake-options] help             # Provide help description about RIDL build system
rake [rake-options] gem              # Build RIDL gem

__HELP_TXT
end

namespace :ridl do
  task :help do
    puts RIDL::HELP
  end
end

desc 'Provide help description about RIDL build system'
task :help => 'ridl:help'
