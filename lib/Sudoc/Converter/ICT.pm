# Copyright (C) 2011 Tamil s.a.r.l. - http://www.tamil.fr
#
# This file is part of Chargeur SUDOC Koha.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

package Sudoc::Converter::ICT;
use Moose;

extends 'Sudoc::Converter';

use MARC::Moose::Field::Std;
use YAML;


# Création des exemplaires Koha en 995 en fonction des données locales SUDOC
after 'itemize' => sub {
    my ($self, $record) = @_;

    #print Dump($self->item);

    # On reprend tout, donc on efface les exemplaires créés avec la
    # logique par défaut
    $record->fields( [ grep { $_->tag ne '995' } @{$record->fields} ] );

    # On crée les exemplaires à partir de 930, 915 et 999
    my $myrcr = $self->sudoc->c->{$self->sudoc->iln}->{rcr};
    my $f999; # Le champ 999 courant
    my $subf;   # Les sous-champs en cours de construction
    my $append = sub { # Ajout à $subf d'un sous-champ de $f999
        my $letter = shift;
        return unless $f999;
        my $value = $f999->subfield($letter);
        return unless $value;
        push @$subf, [ $letter => $value ];
    };
    while ( my ($rcr, $item_rcr) = each %{$self->item} ) {
        my $branch = $myrcr->{$rcr};
        while ( my ($id, $ex) = each %$item_rcr ) { # Les exemplaires d'un RCR
            $subf = [];
            $f999 = $ex->{999};

            $append->('a');

            # $b et $c = Les codes de site Koha
            push @$subf, [ b => $branch ], [ c => $branch ];

            # $d = Le code rétroconversion de 991$a
            my $value = $ex->{991};
            if ( $value ) {
                $value = $value->subfield('a');
                push @$subf, [ d => $value ] if $value;
            }

            $append->('e');

            # $f Code à barres
            # On prend le code à barres en 915$b, et s'il n'y en a pas on prend
            # l'EPN SUDOC ($id)
            $value = $ex->{915};
            $value = $value->subfield('b')  if $value;
            $value = $id unless $value;
            push @$subf, [ f => $value ];

            # $j Numéro d'inventaire
            $append->('j');

            # $k Cote = 930$a
            $value = $ex->{930}->subfield('a');
            push @$subf, [ k => $value ];

            # On copie telles quelles toutes les lettres de 999 en 995
            # pour l'intervalle l..z
            $append->($_) for ( "l" .. "z" );
            $record->append( MARC::Moose::Field::Std->new(
                tag => '995',
                subf => $subf ) );
        }
    }

};


# Les champs à supprimer de la notice entrante.
my @todelete = qw( 915 917 930 991 999);
 
after 'clean' => sub {
    my ($self, $record) = @_;

    # Suppression des champs SUDOC dont on ne veut pas dans le catalogue
    # Koha
    $record->fields( [ grep { not $_->tag ~~ @todelete } @{$record->fields} ] );

    # On détermine le type de doc biblio
    my $tdoc;
    if ( my $field = $record->field('995') ) {
        $tdoc = $field->subfield('r');
        $tdoc = 'MONO' unless $tdoc;
    }
    if ( $tdoc ) {
        $record->append( MARC::Moose::Field::Std->new(
            tag => '915', subf => [ [ a => $tdoc ], [ b => '0' ] ] ) );
    }
};

1;
