package Koha::Contrib::Sudoc::PPNize::Reader;
# ABSTRACT: Reader du fichier ABES d'équivalence PPN biblionumber

use Moose;

with 'MooseX::RW::Reader::File';


sub read {
    my $self = shift;

    my $fh = $self->fh;
    
    my $line = <$fh>;
    return 0 unless $line;

    chop $line;
    my ($ppn, $biblionumber) = $line =~ /PPN (.*) : (.*)/;
    return { ppn => $ppn, biblionumber => $biblionumber };
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;