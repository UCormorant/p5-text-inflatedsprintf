use utf8;
use strict;
use Test::More tests => 4;

use Text::InflatedSprintf;

subtest 'new' => sub {
    my $fmt;

    eval { Text::InflatedSprintf->new() };
    ok($@, 'fail test');

    $fmt = Text::InflatedSprintf->new({ format => "%(text)s" });
    ok($fmt, 'pass test');

    can_ok($fmt, qw(
        format
        set_format
    ));
};

subtest 'format' => sub {
    my $fmt = Text::InflatedSprintf->new({ format => "%(text)s" });

    my $text = $fmt->format({ text => 'Hello!' });
    is($text, 'Hello!', 'do format');
};

subtest 'set_format' => sub {
    my $fmt = Text::InflatedSprintf->new({ format => "%(text)s" });

    my $text = $fmt->set_format("Hello, %(text)s!")->format( text => 'world' );
    is($text, 'Hello, world!', 'do set_format');
};

subtest 'inflated_sprintf' => sub {
    ok(defined &inflated_sprintf, 'export inflated_sprintf');

    is(
        inflated_sprintf("%(package)s %(version)s",
            package => 'Text::InflatedSprintf',
            version => Text::InflatedSprintf->VERSION,
        ),
        "Text::InflatedSprintf ".Text::InflatedSprintf->VERSION,
        "do inflated_sprintf",
    );

    is(
        inflated_sprintf({
                format => "%(package)s %(version)s",
                maxlength => 25,
            },
            package => 'Text::InflatedSprintf',
            version => Text::InflatedSprintf->VERSION,
        ),
        "",
        "do inflated_sprintf with option",
    );
};

done_testing;
