package Conversion;
use Moose;

use Converter;

extends 'FileProcess';


# Le lecteur d'enregistrements utilisé par la conversion
has reader => (
    is => 'rw', 
    #isa => 'RecordReader',
);

# Le writer dans lequel écrie les enregistremens convertis
has writer => ( 
    is => 'rw',
    #isa => 'RecordWriter',
);

# Le converter qui transforme les notices en notices MARC
has converter => ( isa => 'Converter', is => 'rw' );



sub run  {
    my $self = shift;
    $self->writer->begin();
    $self->SUPER::run();
};


sub process {
    my $self = shift;
    my $record = $self->reader->read();
    if ( $record ) {
        $self->SUPER::process();
        my $converter = $self->converter;
        my $converted_record = 
            $converter ? $converter->convert( $record ) : $record;
        unless ( $converted_record ) {
            # Conversion échouée mais il reste des enregistrements
            # print "NOTICE NON CONVERTIE #", $self->count(), "\n";
            return 1;
        }
        $self->writer->write( $converted_record );
        return 1;
    }
    $self->writer->end();
    return 0;
}


no Moose;
__PACKAGE__->meta->make_immutable;

1;

=head1 Conversion

Class managing a conversion task.

=head1 COPYRIGHT AND LICENSE

Copyright 2011 by Tamil, s.a.r.l.

L<http://www.tamil.fr>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.