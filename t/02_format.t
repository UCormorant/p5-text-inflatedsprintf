use utf8;
use strict;
use Test::More tests => 5;
use Test::Base::Less;

use Text::InflatedSprintf;

filters {
    data     => ['eval'],
    format   => ['trim'],
    expected => ['trim'],
};

run {
    my $block = shift;
    my $expected = $block->expected;
    if ($expected =~ s/^like:\s*//i) {
        like(inflated_sprintf($block->format, $block->data), qr{$expected}, $block->name);
    }
    else {
        is(inflated_sprintf($block->format, $block->data), $expected, $block->name);
    }
};

done_testing;


__DATA__

=== named sprintf
--- data
+{
    char_a => 97,          # a character with the given number
    char_b => 98,
    char_c => 99,
    string => 'test text', # a string
    decimal => -1000,      # a signed integer, in decimal
    u_decimal => 1000,     # an unsigned integer, in decimal
    octal => 1000,         # an unsigned integer, in octal
    hexadecimal => 1000,   # an unsigned integer, in hexadecimal
    s_notation => 1000,    # a floating-point number, in scientific notation
    f_notation => 0.0102,  # a floating-point number, in fixed decimal notation
    upper_x => 1000,       # like %x, but using upper-case letters
    upper_e => 1000,       # like %e, but using an upper-case "E"
    binary => 100,         # an unsigned integer, in binary
    upper_b => 100,        # like %b, but using an upper-case "B" with the # flag
}
--- format
%% %(char_a)c %(char_b)c %(char_c)c
%(string)s
%(decimal)d
%(u_decimal)u
%(octal)o
%(hexadecimal)#x
%(s_notation)#.2e
%(f_notation)#.2f
%(binary)#b
%(upper_x)#X
%(upper_e)#.2E
%(upper_b)#B
--- expected
% a b c
test text
-1000
1000
1750
0x3e8
1.00e+003
0.01
0b1100100
0X3E8
1.00E+003
0B1100100

=== take array
--- data
+{
    array => [qw/a b c/],
}
--- format
%%(array)s: %(array)s %(array)s %(array)s %(array)s %(array)s
--- expected
%(array)s: a b c a b

=== take hash
--- data
+{
    hash => {
        foo => 'hoge',
        bar => 'fuga',
        baz => 'piyo',
    },
}
--- format
%%(hash)s: %(hash)s %(hash)s %(hash)s %(hash)s %(hash)s
--- expected
like: %\(hash\)s: \w{4} \w{4} \w{4} \w{4} \w{4}

=== array inflation
--- data
+{
    char => [97 .. 103],
}
--- format
%%(char)c: %(char)c%{, %(char)c%{ + %(char)c}}*
--- expected
%(char)c: a, b + c, d + e, f + g

=== hash inflation
--- data
+{
    hash => {
        foo => 'hoge',
        bar => 'fuga',
        baz => 'piyo',
        hash => {
            foo => 'hoge',
            bar => 'fuga',
            baz => 'piyo',
        },
    }
}
--- format
%%{|hash|}:%{|hash| %(foo)s %(bar)s %(baz)s %(hash)s}*
--- expected
like: %{\|hash\|}: (hoge fuga piyo) \w{4} \1 \w{4} \1 \w{4}
