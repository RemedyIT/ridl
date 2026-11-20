require 'minitest/autorun'
require 'ridl/runner'
require 'ridl/require'
require_relative '../ridlbe/test/config'

class HomeTest < Minitest::Test
  def test_retains_declared_primary_key
    parser = IDL::Parser.new(idlversion: 3, ignore_pidl: true)
    parser.parse(<<~IDL)
      valuetype Key {
        public long id;
      };

      component Worker {};

      home WorkerHome manages Worker primarykey Key {};
    IDL

    root = parser.instance_variable_get(:@d).root
    home = root.resolve('WorkerHome')
    assert_equal 'Key', home.primarykey.name
  end
end
