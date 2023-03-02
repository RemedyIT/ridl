# encoding: utf-8
# Encoding.default_internal = 'UTF-8'

# :main: README.rdoc

#--------------------------------------------------------------------
# ridl.rb - main file for Ruby IDL compiler
#
# Author: Martin Corino
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the RIDL LICENSE which is
# included with this program.
#
# Copyright (c) Remedy IT Expertise BV
#--------------------------------------------------------------------
require 'ridl/require'

##
# RIDL is a Ruby library implementing an OMG \IDL parser/compiler
# frontend with support for pluggable (and stackable) backends.
#
# RIDL itself implements an \IDL parser (RACC based) in IDL::Parser in
# combination with IDL::Scanner, syntax tree classes under IDL::AST,
# type classes under IDL::Type and expression classes under
# IDL::Expression.
# Furthermore RIDL implements a number of support classes useful in
# the implementation of backends for RIDL.
#
# RIDL does *not* implement any standard backend to handle things like
# code generation and/or documentation generation but instead provides
# a framework for user defined pluggable backends.
# Known backends for RIDL are the R2CORBA RIDL backend and the IDL2C++11
# backend.
#
module IDL
end

# load RIDL runner/initializer
require 'ridl/runner'

# initialize RIDL
IDL.init
