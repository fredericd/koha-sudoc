package RecordWriter;
use Moose;


has count => (
    is => 'rw',
    isa => 'Int',
    default => 0
);


sub begin { }

sub end { }

sub write {
    my $self = shift;

    $self->count( $self->count + 1 );
    
    return 0;
}

__PACKAGE__->meta->make_immutable;

1;


=head1 NAME

RecordWriter - Class for writing whatever records into whatever

=head1 SYNOPSIS

  my $writer = RecordWriter->new();
  while ( $record = $reader->read() ) {
    $writer->write( $record );
  }
  print "Processes record: ", $writer->count, "\n";

=head1 COPYRIGHT AND LICENSE

Copyright 2011 by Tamil, s.a.r.l.

L<http://www.tamil.fr>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
