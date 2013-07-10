use utf8;
use strict;
use Test::More tests => 3;
use Test::Difflet;

use Text::InflatedSprintf;

subtest '#new' => sub {
    my $fmt = Text::InflatedSprintf->new({ format => "%(text)s" });
    ok($fmt, 'new formatter');

    is_deeply(
        $fmt->{_context},
        [{ content => '%(text)s', }],
        'check _context',
    );
};

subtest '#format' => sub {
    my $fmt = Text::InflatedSprintf->new({ format => "%(text)s" });
    can_ok($fmt, qw(
        format
    ));

    is($fmt->format({ text => 'Hello!' }), 'Hello!', 'check format');
};

subtest 'inflated_sprintf' => sub {
    is(
        inflated_sprintf("%(package)s %(version)s", {
            package => 'Text::InflatedSprintf',
            version => Text::InflatedSprintf->VERSION
        }),
        "Text::InflatedSprintf ".Text::InflatedSprintf->VERSION,
        "check inflated_sprintf",
    );
};

done_testing();
