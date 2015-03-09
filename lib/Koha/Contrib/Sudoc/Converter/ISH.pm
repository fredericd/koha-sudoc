package Koha::Contrib::Sudoc::Converter::ISH;
# ABSTRACT: Convertisseur spécifique

use Moose;

extends 'Koha::Contrib::Sudoc::Converter';


# Moulinette SUDOC
has sudoc => ( is => 'rw', isa => 'Sudoc', required => 1 );




# Création des exemplaires Koha en 995 en fonction des données locales SUDOC
sub itemize {
    my ($self, $record) = @_;
}




1;
