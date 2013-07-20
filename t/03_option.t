use utf8;
use strict;
use Test::More tests => 2;
use Test::Base::Less;

use Text::InflatedSprintf;

subtest 'kv_separator' => sub {
    my $format = "%(hash)s, %(hash)s, %(hash)s, %(hash)s, %(hash)s";
    my $data = {
        hash => {
            a => 97,
            b => 98,
            c => 99,
            d => 100,
            e => 101,
        },
    };

    my $set_kv = Text::InflatedSprintf->new(
        format => $format,
        kv_separator => " => ",
    );

    like($set_kv->format($data), qr{\w => \d+, \w => \d+, \w => \d+, \w => \d+, \w => \d+}, 'set kv_separator');

    my $unset_kv = Text::InflatedSprintf->new(
        format => $format,
    );

    like($unset_kv->format($data), qr{\d+, \d+, \d+, \d+, \d+}, 'unset kv_separator');
};

subtest 'depth_limit' => sub {
    my $data = { text => 'depth_limit test' };
    my $format = "%{%{%{%{%{%(text)s}}}}}";
    eval {
        my $tis = Text::InflatedSprintf->new(
            format => $format,
        );
        $tis->format($data);
    };
    ok(!$@, 'default depth_limit is 5');

    eval {
        my $tis = Text::InflatedSprintf->new(
            format => $format,
            depth_limit => 2,
        );
        $tis->format($data);
    };
    ok($@, 'set depth_limit 2');

    eval {
        my $tis = Text::InflatedSprintf->new(
            format => $format,
            depth_limit => 0,
        );
        $tis->format($data);
    };
    ok($@, 'set depth_limit 0');

    $format = "%(text)s";
    eval {
        my $tis = Text::InflatedSprintf->new(
            format => $format,
            depth_limit => 0,
        );
        $tis->format($data);
    };
    ok(!$@, 'pass depth_limit 0');
};

done_testing;
