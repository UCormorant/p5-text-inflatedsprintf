package Text::InflatedSprintf;
use 5.008005;
use utf8;
use strict;
use warnings;

our $VERSION = "0.03";

use parent qw(Exporter);
our @EXPORT = qw(inflated_sprintf);

use bytes ();
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
            pop @{$parent->{content}} if $current->{content} eq '';
            $current = $const->('');
            $current->{parent} = $const->([$current]);
            $mk_relationship->($current->{parent}, $parent);
            $parent = $current->{parent};

            $depth++;
            Carp::croak 'recursive error: too depth' if $self->{depth_limit} > -1 && $depth > $self->{depth_limit};
            $parent->{name} = $name if $name;
        }
        elsif ($depth and $close) {
            pop @{$parent->{content}} if $current->{content} eq '';
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
    pop @{$parent->{content}} if $current->{content} eq '';

    Carp::croak 'syntax error: mismatch tagging' if $depth;

    my $mk_requirement; $mk_requirement = sub {
        for my $c (@{$_[0]{content}}) {
            if (_is_array($c->{content})) {
                $mk_requirement->($c);
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
            delete $c->{parent};
        }
    };
    $mk_requirement->($context);

    $self->{_context} = $context;
}

sub format {
    my $self = shift;
    my %data = scalar @_ == 1 ? %{+shift} : @_;

    $self->{_data} = \%data;
    $self->{_index} = {};
    $self->{_index_value} = {};
    $self->{_loop} = {};

    my @content_list;
    my $state = {
        formatted_content => ['DUMMY'],
        replace_index => 0,
    };
    while ($self->_format($self->{_context}, \%data, $state, \@content_list)) {
        $state = {
            formatted_content => ['DUMMY'],
            replace_index => 0,
        };
    };
    push @content_list, join "", @{$state->{formatted_content}};

    wantarray ? @content_list : $content_list[0];
}

sub _format {
    my ($self, $context, $data, $state, $content_list) = @_;

    my @formatted_content;
    for my $c (@{$context->{content}}) {
        if (_is_array($c->{content})) {
            push @formatted_content, $c;
        }
        else {
            my $not_loop = 1;
            for my $name (keys %{$c->{require}}) {
                if (defined $data->{$name} and (_is_array($data->{$name}) or _is_hash($data->{$name}))) {
                    my $refaddr = refaddr $data->{$name};
                    if (exists $self->{_loop}{$refaddr}) {
                        $not_loop = 0;
                    }
                }
            }
            if ($not_loop) {
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
    }
    splice @{$state->{formatted_content}}, $state->{replace_index}, 1, @formatted_content;

    my @grep_content_index;
    my @grep_contengt = map {
        my $c = $state->{formatted_content}[$_];
        if (not _is_hash($c)) {
            push @grep_content_index, $_ if $state->{replace_index} <= $_ && $_ <= ($state->{replace_index}+$#formatted_content);
            $c;
        }
        else {
            ();
        }
    } 0 .. $#{$state->{formatted_content}};
    my $text = join "", @grep_contengt;
    if (defined $self->{minlength} and        length $text < $self->{minlength}) {}
    if (defined $self->{minbyte}   and bytes::length $text < $self->{minbyte}) {}
    if (
        defined $self->{maxlength} && $self->{maxlength} < length $text
            or
        defined $self->{maxbyte}   && $self->{maxbyte}   < bytes::length $text
    ) {
        while (
            scalar @grep_content_index
                and
            (not defined $self->{maxlength} or $self->{maxlength} < length $text)
                and
            (not defined $self->{maxbyte}   or $self->{maxbyte}   < bytes::length $text)
        ) {
            splice @grep_contengt, pop @grep_content_index, 1;
            $text = join "", @grep_contengt;
        }
        push @$content_list, $text;
        for my $key (keys %{$context->{require}}) {
            my $refaddr = refaddr $data->{$key};
            if (exists $self->{_index}{$refaddr}) {
                if (not exists $self->{_loop}{$refaddr}) {
                    $self->{_index}{$refaddr}--;
                }
                else {
                    delete $self->{_loop}{$refaddr};
                    $self->{_index}{$refaddr} = $#{$self->{_index_value}{$refaddr}};
                }
            }
        }
        return 1;
    }

    my $index = $state->{replace_index};
    while ($index <= $#{$state->{formatted_content}}) {
        my $c = $state->{formatted_content}[$index];
        if (_is_hash($c)){
            REPEAT: while (1) {
                my $condition = $c->{name} ? $data->{$c->{name}} : $data;

                my %has_loop = ();
                for my $name (keys %{$c->{require}}) {
                    if (defined $data->{$name} and (_is_array($data->{$name}) or _is_hash($data->{$name}))) {
                        $has_loop{$name} = 1;
                    }
                }
                for my $name (keys %has_loop) {
                    my $refaddr = refaddr $condition->{$name};
                    if (exists $self->{_loop}{$refaddr}) {
                        splice @{$state->{formatted_content}}, $index, 1;

                        last REPEAT;
                    }
                }

                $state->{replace_index} = $index;
                return 1 if $self->_format($c, $condition, $state, $content_list);

                for my $name (keys %has_loop) {
                    delete $has_loop{$name} if $self->{_loop}{refaddr $condition->{$name}};
                }

                if ($c->{operator} and scalar keys %has_loop) {
                    $index = ++$state->{replace_index};
                    splice @{$state->{formatted_content}}, $index, 0, $c;
                }
                else {
                    last REPEAT;
                }
            }
        }
        $index++;
    }

    return 0;
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

    if (not exists $self->{_index}{$refaddr}) {
        $self->{_index_value}{$refaddr} = $params->{$name};
    }

    my $index = $self->{_index}{$refaddr}++;
    if ($index >= $#{$self->{_index_value}{$refaddr}}) {
        $self->{_index}{$refaddr} = 0;
        $self->{_loop}{$refaddr} = 1;
    }
    $params->{$name}[$index];
}

sub _hash_loop {
    my ($self, $params, $name) = @_;
    my $refaddr = refaddr $params->{$name};

    if (not exists $self->{_index}{$refaddr}) {
        $self->{_index_value}{$refaddr} = [];
        while (my @k_v = each %{$params->{$name}}) {
            push $self->{_index_value}{$refaddr}, \@k_v;
        }
    }

    my $index = $self->{_index}{$refaddr}++;
    if ($index >= $#{$self->{_index_value}{$refaddr}}) {
        $self->{_index}{$refaddr} = 0;
        $self->{_loop}{$refaddr} = 1;
    }
    my $value = $self->{_index_value}{$refaddr}[$index];
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
