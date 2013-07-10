# NAME

Text::InflatedSprintf - sprintf-like template engine for short messages

# SYNOPSIS

    use version; our $VERSION = qv('v1.2.3');
    use Text::InflatedSprintf;

    my $package_version = inflated_sprintf("%(package)s-%(version)vd", {
        package => __PACKAGE__,
        version => $VERSION,
    });

    print $package_version; # YourModule-1.2.3

# DESCRIPTION

Text::InflatedSprintf is a micro template engine for short messages.

# ACKNOWLEDGEMENTS

The extended syntax for sprintf function was bollowed from
[Text:::Sprintf::Named](http://search.cpan.org/perldoc?Text:::Sprintf::Named) module written by Shlomi Fish. Thank you!

# AUTHOR

U=Cormorant <u@chimata.org>

# LICENSE

Copyright (C) U=Cormorant.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See [perlartistic](http://search.cpan.org/perldoc?perlartistic).
