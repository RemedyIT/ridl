require 'minitest/autorun'
require 'ridl/runner'
require 'ridl/require'
require_relative '../ridlbe/test/config'

class OperationContextTest < Minitest::Test
  def test_retains_declared_context_strings
    parser = IDL::Parser.new(idlversion: 3, ignore_pidl: true)
    parser.parse(<<~IDL)
      interface Example {
        void ping() context ("region", "trace-id");
      };
    IDL

    root = parser.instance_variable_get(:@d).root
    operation = root.resolve('Example').resolve('ping')
    assert_equal ['region', 'trace-id'], operation.context
  end
end
