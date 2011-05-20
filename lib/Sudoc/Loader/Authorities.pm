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

package Sudoc::Loader::Authorities;
use Moose;

extends 'Sudoc::Loader';

use C4::AuthoritiesMarc;
use MARC::Moose::Record;


# On cherche les autorités doublons SUDOC. On renvoie la liste des notices
# Koha correspondantes.
sub doublons_sudoc {
    my ($self, $record) = @_;
    my @doublons;
    # On cherche un 035 avec $9 sudoc qui indique une fusion d'autorité Sudoc
    # 035$a contient le PPN de la notice qui a été fusionnée avec la notice en
    # cours de traitement.
    for my $field ( $record->field('035') ) {
        my $sudoc = $field->subfield('9');
        next unless $sudoc && $sudoc =~ /sudoc/i;
        my $ppn = $field->subfield('a');
        my ($authid, $auth) =
            $self->sudoc->koha->get_auth_by_ppn( $ppn );
        if ($auth) {
            $self->log->notice(
              "  Fusion Sudoc du PPN $ppn de l'autorité Koha " .
              "$authid\n" );
            push @doublons, { ppn => $ppn, authid => $authid, auth => $auth };
        }
    } 
    return \@doublons;
}


sub handle_record {
    my ($self, $record) = @_;

    my $conf = $self->sudoc->c->{$self->sudoc->iln}->{auth};

    my $ppn = $record->field('001')->value;
    $self->log->notice( "Autorité #" . $self->count . " PPN $ppn\n");
    $self->log->debug( $record->as('Text'), "\n" );

    # On détermine le type d'autorité
    my $authtypecode;
    my $typefromtag = $conf->{typefromtag};
    for my $tag ( keys %$typefromtag ) {
        if ( $record->field($tag) ) {
            $authtypecode = $typefromtag->{$tag};
            last;
        }
    }
    unless ( $authtypecode ) {
        $self->warning( "  ERREUR: Autorité sans champ Vedette\n" );
        return;
    }

    # On déplace le PPN de 001 en 009
    $self->sudoc->ppn_move($record, $conf->{ppn_move});

    # FIXME Reset de la connexion tous les x enregistrements
    $self->sudoc->koha->zconn_reset()  unless $self->count % 500;
    
    # Y a-t-il déjà dans la base Koha une autorité ayant ce PPN ?
    my ($authid, $auth) = $self->sudoc->koha->get_auth_by_ppn($ppn);

    # Les doublons SUDOC. Il n'y a qu'un seul cas où on peut en faire quelque
    # chose. Si on a déjà trouvé une autorité Koha ci-dessus, on ne peut rien
    # faire : en effet, on a déjà une cible pour fusionner la notice entrante.
    # S'il y a plus d'un doublon qui correspond à des notices Koha, on ne sait
    # pas à quelle notice Koha fusionner la notice entrante.
    my $doublons = $self->doublons_sudoc($record);
    if ( @$doublons ) {
        if ( $auth || @$doublons > 1 ) {
            $self->log->warning(
                "  Attention ! la notice entrante doit être fusionnée à plusieurs " .
                "notices Koha existantes. A FAIRE MANUELLEMENT\n" );
        }
        else {
            # On fusionne le doublon SUDOC (unique) avec la notice SUDOC entrante
            my $d = shift @$doublons;
            ($authid, $auth) = ($d->{authid}, $d->{auth});
        }
    }

    # Si on a trouvé une autorité correspondante, et une seule, on ajoute son
    # authid à l'autorité entrante afin de forcer sa mise à jour.
    if ( $auth ) {
        $record->append(
            MARC::Moose::Field::Control->new( tag => '001', value => $authid) );
        $self->count_replaced( $self->count_replaced + 1 );
    }

    ($authid) = AddAuthority($record->as('Legacy'), $authid, $authtypecode)
        if $self->doit;
    $authid = 0 unless $authid;
    $self->log->notice(
        ($auth ? "  * Remplace" : "  * Ajout") .
        " authid $authid\n" );
}

1;
