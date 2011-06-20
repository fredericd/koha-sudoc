package RecordReader::File;
use Moose;

use Carp;

extends 'RecordReader';

has file => (
    is => 'rw',
    isa => 'Str',
    trigger => sub {
        my ($self, $file) = @_;
        unless ( -e $file ) {
            croak "File doesn't exist: " . $file;
        }
        $self->{file} = $file;
    }

);



__PACKAGE__->meta->make_immutable;

1;

=head1 NAME

RecordReader::File - A RecordReader subclass, reading a file content.

=head1 COPYRIGHT AND LICENSE

Copyright 2009 by Tamil, s.a.r.l.

L<http://www.tamil.fr>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
