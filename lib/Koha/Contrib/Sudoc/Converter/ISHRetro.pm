package Koha::Contrib::Sudoc::Converter::ISHRetro;
# ABSTRACT: Convertisseur spécifique

use Moose;

extends 'Koha::Contrib::Sudoc::Converter';


override 'merge' => sub {
    my ($self, $sudoc, $koha) = @_;

    my @tags = ( (map { sprintf("6%02d", $_) } ( 0..99 )), '995');
    for my $tag (@tags) {
        my @fields = $sudoc->field($tag); 
        next unless @fields;
        $koha->append(@fields);
    }

    my @all_tags = map { sprintf("%03d", $_) } ( 1..999 );
    for my $tag (@all_tags) {
        next if $tag ~~ @tags || $tag == '410'; # On passe, déjà traité plus haut
        my @fields = $sudoc->field($tag);
        next unless @fields;
        next if $koha->field($tag);
        $koha->append(@fields);
    }

    $sudoc->fields( $koha->fields );
};


# Les champs à supprimer de la notice entrante.
my @todelete = qw(035 917 930 991 999);

after 'clean' => sub {
    my ($self, $record) = @_;

    # Suppression des champs SUDOC dont on ne veut pas dans le catalogue
    $record->fields( [ grep { not $_->tag ~~ @todelete } @{$record->fields} ] );
};


1;
