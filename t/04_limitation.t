use utf8;
use strict;
use Test::More tests => 4;
use Test::Base::Less;

use Text::InflatedSprintf;

filters {
    configure => ['eval'],
    data      => ['eval'],
    format    => ['trim'],
    expected  => ['trim'],
};

run {
    my $block = shift;
    (my $expected = $block->expected) =~ s/\n$//;
    my $instance = Text::InflatedSprintf->new( format => 'DUMMY', %{$block->configure} );
    my $got = join "\n", $instance->set_format($block->format)->format($block->data);
    is($got, $expected, $block->name);
};

done_testing;


__DATA__

=== maxbyte: unset on_over (flat)
--- configure
+{
    maxbyte => 10,
}
--- data
+{
    array => [97..122],
}
--- format: %{%(array)c}*
--- expected
abcdefghij
klmnopqrst
uvwxyz

=== maxbyte: unset on_over (nest)
--- configure
+{
    maxbyte => 40,
}
--- data
+{
    scalar => 'list',
    hash => {
        scalar => 'name',
        array => [qw(
            Earlean
            Jeremy
            Evelyn
            Zonia
            Nickolas
            Ashley
            Bryanna
            Leah
            Iola
            Lilly
            Etta
            Benita
            Marguerita
            Orville
            Gregg
            Rosemarie
            Gennie
            Monte
            Meta
            Merissa
        )],
    }
}
--- format: %(scalar)s: %{|hash|%(scalar)s=%{%(array)s%{, %(array)s}*}}
--- expected
list: name=Earlean, Jeremy, Evelyn
list: name=Zonia, Nickolas, Ashley
list: name=Bryanna, Leah, Iola, Lilly
list: name=Etta, Benita, Marguerita
list: name=Orville, Gregg, Rosemarie
list: name=Gennie, Monte, Meta, Merissa

=== maxlengt: unset on_over (flat)
--- configure
+{
    maxlength => 5,
}
--- data
+{
    array => [qw/あ い う え お か き く け こ さ し す せ そ た ち つ て と な に ぬ ね の/],
}
--- format: %{%(array)s}*
--- expected
あいうえお
かきくけこ
さしすせそ
たちつてと
なにぬねの

=== maxlength: unset on_over (nest)
--- configure
+{
    maxlength => 19,
}
--- data
+{
    scalar => 'リスト',
    hash => {
        scalar => '名前',
        array => [qw(
            宏太
            斗真
            英雄
            稜駿
            智弘
            亮太
            龍一
            健一
            二郎
            康晴
            陽菜
            亜沙美
            沙紀
            水華
            梨沙子
            あゆみ
            千鶴
            みなみ
            桃子
            のぞみ
        )],
    }
}
--- format: %(scalar)s: %{|hash|%(scalar)s=%(array)s%{, %(array)s}*}
--- expected
リスト: 名前=宏太, 斗真, 英雄
リスト: 名前=稜駿, 智弘, 亮太
リスト: 名前=龍一, 健一, 二郎
リスト: 名前=康晴, 陽菜, 亜沙美
リスト: 名前=沙紀, 水華, 梨沙子
リスト: 名前=あゆみ, 千鶴
リスト: 名前=みなみ, 桃子
リスト: 名前=のぞみ

