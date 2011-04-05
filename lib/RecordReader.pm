package RecordReader;
use Moose;


has count => (
    is => 'rw',
    isa => 'Int',
    default => 0
);


sub read {
    my $self = shift;

    $self->count( $self->count + 1 );
    
    return 1;
}

__PACKAGE__->meta->make_immutable;

1;

=head1 NAME

RecordReader - A class reading records from whatever source

=head1 SYNOPOSYS

  my $reader = RecordReader::File::Iso2709( file => 'foo.iso' );
  while ( $record = $reader->read() ) {
     print $record->as_formatted(), "\n";
  }

=head1 COPYRIGHT AND LICENSE

Copyright 2009 by Tamil, s.a.r.l.

L<http://www.tamil.fr>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
