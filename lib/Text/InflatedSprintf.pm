package Text::InflatedSprintf;
use 5.008005;
use utf8;
use strict;
use warnings;

our $VERSION = "0.02";

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

sub inflated_sprintf {
    __PACKAGE__->new( format => +shift )->format(@_);
}

sub new {
    my $class = shift;
    my %args = scalar @_ == 1 ? %{+shift} : @_;
    my $self = bless {
        format => '',

        minbyte => undef,
        maxbyte => undef,
        minlength => undef,
        maxlength  => undef,

        on_less => undef,
        on_over => undef,

        depth_limit => 5,
        kv_separator => undef,

        %args,
    }, $class;

    $self->set_format;
    $self;
}

sub set_format {
    my $self = shift;

    $self->{format} = $_[0] if defined $_[0];

    Carp::croak "no format given" if $self->{format} eq '';

    $self->_mk_context;
    $self;
}

sub _mk_context {
    my ($self) = @_;

    $self->{_context} = {};
    $self->{_require} = {};
    $self->{_index} = {};
    $self->{_loop} = {};

    my $const = sub { +{
        content => +shift,
        name => undef,
        operator => undef,
        parent => undef,
        require => {},
    } };
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
        }
        elsif ($depth and $close) {
            $parent->{operator} = $operator if $operator;

            $current = $const->('');
            $mk_relationship->($current, $parent->{parent});
            $parent = $parent->{parent};

            $depth--;
        }
        else {
            $current->{content} .= $match;
        }
    }

    Carp::croak 'syntax error: mismatch tagging' if $depth;

    my $mk_requirement; $mk_requirement = sub {
        for my $c (@{$_[0]}) {
            if (ref $c->{content} and reftype $c->{content} eq 'ARRAY') {
                $mk_requirement->($c->{content});
            }
            else {
                while ($c->{content} =~ /$REGEX{sprintf}/gc) {
                    my $conv = $1 || '';
                    my $name = $2 || '';
                    my $conv_prefix = $3 || '';
                    my $conv_letter = $4 || '';
                    next if $conv eq '%';

                    $c->{parent}{require}{$name} = $conv_letter;
                }
            }
        }
    };
    $mk_requirement->($context->{content});

    my $del_relationship; $del_relationship = sub {
        for my $c (@{$_[0]}) {
            delete $c->{parent};
            $del_relationship->($c->{content}) if ref $c->{content} and reftype $c->{content} eq 'ARRAY';
        }
    };
    $del_relationship->($context->{content});

    $self->{_context} = $context->{content};
}

sub format {
    my $self = shift;
    my %data = scalar @_ == 1 ? %{+shift} : @_;

    my $formatted_content = $self->_format($self->{_context}, \%data);

    return join "", @$formatted_content;
}

sub _format {
    my ($self, $context, $data) = @_;

    my @formatted_content;
    for my $c (@$context) {
        if (_is_array($c->{content})) {
            my %has_loop = ();
            for my $name (keys %{$c->{require}}) {
                if (defined $data->{$name} and (_is_array($data->{$name}) or _is_hash($data->{$name}))) {
                    $has_loop{$name} = 1;
                }
            }
            while (1) {
                my $condition = $c->{name} ? $data->{$c->{name}} : $data;
                my $content = $self->_format($c->{content}, $condition);
                push @formatted_content, @$content;

                for my $name (keys %has_loop) {
                    delete $has_loop{$name} if $self->{_loop}{refaddr $condition->{$name}};
                }

                last unless $c->{operator} and scalar keys %has_loop;
            }
        }
        else {
            my $content = $c->{content};
            $content =~ s/$REGEX{sprintf}/
                $self->_conversion({
                    context => $context,
                    named_params => $data,
                    conv => $1,
                    name => $2,
                    conv_prefix => $3,
                    conv_letter => $4,
                })
            /ge;
            push @formatted_content, $content;
        }
    }

    \@formatted_content;
}

sub _conversion {
    my ($self, $args) = @_;

    if ($args->{conv} eq "%") {
        return "%";
    }
    else {
        my $context = $args->{context};
        my $name = $args->{name};
        my $params = $args->{named_params};
        my $exists = exists $params->{$args->{name}};
        my $is_array = _is_array($params->{$args->{name}});
        my $is_hash  = _is_hash($params->{$args->{name}});
        my $is_code  = _is_code($params->{$args->{name}});

        my $format = "%" . $args->{conv_prefix} . $args->{conv_letter};
        my $replace = $is_array ? $self->_array_loop($params, $name) :
                      $is_hash  ? $self->_hash_loop($params, $name)  :
                      $is_code  ? $params->{$args->{name}}->($self, $context, $params) :
                      $exists   ? $params->{$args->{name}}           : "";

        return sprintf $format, $replace;
    }
}

sub _array_loop {
    my ($self, $params, $name) = @_;
    my $refaddr = refaddr $params->{$name};
    my $index = $self->{_index}{$refaddr}++;
    if ($index >= $#{$params->{$name}}) {
        $self->{_index}{$refaddr} = 0;
        $self->{_loop}{$refaddr} = 1;
    }
    $params->{$name}[$index];
}

sub _hash_loop {
    my ($self, $params, $name) = @_;
    my $refaddr = refaddr $params->{$name};
    my $value = $self->{_index}{$refaddr};
    my @index = each %{$params->{$name}};
    if (not defined $value) {
        $value = \@index;
        @index = each %{$params->{$name}};
    }
    if (not defined $index[0]) {
        @index = each %{$params->{$name}};
        $self->{_loop}{$refaddr} = 1;
    }
    $self->{_index}{$refaddr} = \@index;
    (not defined $self->{kv_separator}) ? $value->[1] : join $self->{kv_separator}, @$value;
}

sub _is_array {
    (ref $_[0] and reftype $_[0] eq 'ARRAY');
}

sub _is_hash {
    (ref $_[0] and reftype $_[0] eq 'HASH');
}

sub _is_code {
    (ref $_[0] and reftype $_[0] eq 'CODE');
}

1;
__END__

=encoding utf-8

=head1 NAME

Text::InflatedSprintf - sprintf-like template library for short messages

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
