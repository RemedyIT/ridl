require 'minitest/autorun'
require 'ridl/require'

class FixedConstantTest < Minitest::Test
  def parse_idl(idl)
    IDL::Parser.new.parse(idl)
  end

  def test_accepts_representable_fixed_constants
    parse_idl(<<~IDL)
      typedef fixed<5,5> fraction;
      const fraction value = 0.12345;
      typedef fixed<5,2> amount;
      const amount trailing_zeroes = 1.2300d;
    IDL
  end

  def test_rejects_excess_fractional_digits
    error = assert_raises(IDL::ParseError) do
      parse_idl(<<~IDL)
        typedef fixed<5,2> amount;
        const amount value = 1.234;
      IDL
    end

    assert_match(/fixed<5,2>/, error.message)
  end

  def test_rejects_excess_integral_digits
    error = assert_raises(IDL::ParseError) do
      parse_idl(<<~IDL)
        typedef fixed<5,5> fraction;
        const fraction value = 12345;
      IDL
    end

    assert_match(/fixed<5,5>/, error.message)
  end
end
