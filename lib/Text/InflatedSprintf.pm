package Text::InflatedSprintf;
use 5.008005;
use utf8;
use strict;
use warnings;

our $VERSION = "0.01";

use parent qw(Exporter);

our @EXPORT = qw(inflated_sprintf);

use Carp ();
use Scalar::Util qw(reftype refaddr);

our $REGEX_BEGIN   = '%';
our $REGEX_OPEN    = '{';
our $REGEX_CLOSE   = '}';
our $REGEX_TAGNAME = qr{[a-zA-Z_]\w*};
our $REGEX_OPRATOR = qr{[*+?]};
our $REGEX_CONVPRE = qr{[\+\-\.\#\d\sLVhjlqtvz]*};
our $REGEX_CONVLET = qr{[BDEFGOUXbcdefgiopsux]};
our $REGEX_ESCAPE  = $REGEX_BEGIN;
our %REGEX = (
    syntax => qr/( # \1
        # 開始と終了以外
        [^$REGEX_BEGIN$REGEX_CLOSE]+
      |
        # 開始のエスケープ
        $REGEX_ESCAPE
        $REGEX_BEGIN
      |
        # 終了のエスケープ
        $REGEX_ESCAPE
        $REGEX_CLOSE
      |
        # 開始
        $REGEX_BEGIN
        (?:
            ($REGEX_OPEN) # \2
            (?:\|($REGEX_TAGNAME)\|)? # \3
        )?
      |
        # 終了
        ($REGEX_CLOSE) # \4
        ($REGEX_OPRATOR)?  # \5
      |
        # タグの回収
        [$REGEX_BEGIN$REGEX_CLOSE]
    )/x,

    sprintf => qr/
        # 開始
        $REGEX_BEGIN
        ( # \1
            $REGEX_ESCAPE
          |
            \(($REGEX_TAGNAME)\) # \2
            ($REGEX_CONVPRE)     # \3
            ($REGEX_CONVLET)     # \4
        )
    /x,
);

sub new {
    my $class = shift;
    my %args = @_ == 1 ? %{$_[0]} : @_;
    my $self = bless {
        minbyte => undef,
        maxbyte => undef,
        minlength => undef,
        maxlength  => undef,

        under_code => undef,
        over_code => undef,

        depth_limit => 5,
        kv_separator => ':',
    }, $class;

    $self->{minbyte} = delete $args{minbyte} if exists $args{minbyte};
    $self->{maxbyte} = delete $args{maxbyte} if exists $args{maxbyte};
    $self->{minlength} = delete $args{minlength} if exists $args{minlength};
    $self->{maxlength} = delete $args{maxlength} if exists $args{maxlength};

    $self->{depth_limit} = delete $args{depth_limit} if exists $args{depth_limit};
    $self->{kv_separator} = delete $args{kv_separator} if exists $args{kv_separator};

    $self->{format} = delete $args{format} || Carp::croak "format";
    $self->_mk_context;

    $self;
}

sub _mk_context {
    my ($self) = @_;

    my $const = sub { +{ content => +shift } };
    my $mk_relationship = sub {
        $_[0]{parent} = $_[1];
        push @{$_[1]{content}}, $_[0];
    };

    my $context = $const->([]);
    my $current = $const->('');
    my $parent = $context;
    $mk_relationship->($current, $parent);

    my $depth = 0;
    while ($self->{format} =~ /$REGEX{syntax}/gc) {
        my $match    = $1 || '';
        my $open     = $2 || '';
        my $name     = $3 || '';
        my $close    = $4 || '';
        my $operator = $5 || '';

        if ($open) {
            $current = $const->('');
            $current->{parent} = $const->([$current]);
            $mk_relationship->($current->{parent}, $parent);
            $parent = $current->{parent};

            $depth++;
            Carp::croak 'recursive error: too depth' if $self->{depth_limit} > -1 && $depth > $self->{depth_limit};
            $parent->{name} = $name if $name;
            next;
        }

        if ($depth and $close) {
            $parent->{operator} = $operator if $operator;

            $current = $const->('');
            $mk_relationship->($current, $parent->{parent});
            $parent = $parent->{parent};

            $depth--;
            next;
        }

        $current->{content} .= $match;
    }

    Carp::croak 'syntax error: mismatch tagging' if $depth;

    $self->{_context} = $context->{content};
    my $del; $del = sub {
        for my $c (@{$_[0]}) {
            delete $c->{parent}; $del->($c->{content}) if ref $c->{content} and reftype $c->{content} eq 'ARRAY';
        }
    };
    $del->($self->{_context});
}

sub format {
    my ($self, $data) = @_;

    _format($self->{_context}, $data);
}

sub _format {
    my ($context, $data) = @_;

    my @formatted_content;
    for my $content (@$context) {
        if (ref $content->{content} and reftype $content->{content} eq 'ARRAY') {
           my $formatted_content = _format($context->{content}, $data);
           $data->{_formatted_content_tag($formatted_content)} = $formatted_content;
            push @formatted_content, $formatted_content;
        }
        else {
            push @formatted_content, $content->{content};
        }
    }

    my $format = join "", @formatted_content;

    $format =~ s/$REGEX{sprintf}/
        _conversion({
            named_params => $data,
            conv => $1,
            name => $2,
            conv_prefix => $3,
            conv_letter => $4,
        })
        /ge;

    return $format;
}

sub _conversion {
    my $args = shift;

    if ($args->{conv} eq "%") {
        return "%";
    }
    else {
        my $format = "%" . $args->{conv_prefix} . $args->{conv_letter};
        return sprintf $format, $args->{named_params}->{$args->{name}};
    }
}

sub _formatted_content_tag {
    sprintf "%%(__fmt_tag_%s)s", refaddr $_[0];
}

sub inflated_sprintf {
    __PACKAGE__->new({ format => $_[0] })->format($_[1]);
}

1;
__END__

=encoding utf-8

=head1 NAME

Text::InflatedSprintf - sprintf-like template engine for short messages

=head1 SYNOPSIS

    use version; our $VERSION = qv('v1.2.3');
    use Text::InflatedSprintf;

    my $package_version = inflated_sprintf("%(package)s-%(version)vd", {
        package => __PACKAGE__,
        version => $VERSION,
    });

    print $package_version; # YourModule-1.2.3

=head1 DESCRIPTION

Text::InflatedSprintf is a micro template engine for short messages.

=head1 ACKNOWLEDGEMENTS

The extended syntax for sprintf function was bollowed from
L<Text:::Sprintf::Named> module written by Shlomi Fish. Thank you!

=head1 AUTHOR

U=Cormorant E<lt>u@chimata.orgE<gt>

=head1 LICENSE

Copyright (C) U=Cormorant.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=cut
