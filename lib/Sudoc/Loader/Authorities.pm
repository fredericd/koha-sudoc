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

use 5.010;
use utf8;
use C4::AuthoritiesMarc;
use MARC::Moose::Record;
use Locale::TextDomain('fr.tamil.sudoc');


sub handle_record {
    my ($self, $record) = @_;

    # FIXME: Ici et pas en-tête parce qu'il faut que l'environnement Shell soit
    # déjà fixé avant de charger ces modules qui ont besoin de KOHA_CONF et qui
    # le garde
    use C4::Biblio;
    use C4::Items;

    my $conf = $self->sudoc->c->{$self->sudoc->iln}->{auth};

    # FIXME Reset de la connexion tous les x enregistrements
    $self->sudoc->koha->zconn_reset()  unless $self->count % 100;

    my $ppn = $record->field('001')->value;
    $self->log->notice(
        __x("Authority #{count} PPN {ppn}",
            count => $self->count, ppn => $ppn) . "\n");
    $self->log->debug( $record->as('Text') );

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
        $self->warning( __"  ERROR: Authority without heading" . "\n" );
        return;
    }

    # On déplace le PPN de 001 en 009
    $self->sudoc->ppn_move($record, $conf->{ppn_move});

    # Y a-t-il déjà dans la base Koha une autorité ayant ce PPN ?
    # Si oui, on ajoute son authid à l'autorité entrante afin de forcer sa mise
    # à jour.
    my ($authid, $auth) = $self->sudoc->koha->get_auth_by_ppn($ppn);
    if ( $auth ) {
        $record->append(
            MARC::Moose::Field::Control->new( tag => '001', value => $authid) );
        $self->count_replaced( $self->count_replaced + 1 );
    }
    else {
        $self->count_added( $self->count_added + 1 );
    }

    if ( $self->doit ) {
        my $legacy = $record->as('Legacy');
        # FIXME: Bug SUDOC, certaines notices UTF8 n'ont pas 50 en position 13
        my $field = $legacy->field('100');
        if ( $field ) {
            my $value = $field->subfield('a');
            my $enc = substr($value, 13, 2);
            if ( $enc ne '50' ) {
                $self->log->warning(
                    __"  Warning! bad encoding in position 13. Fix it." . "\n" );
                substr($value, 13, 2) = '50';
                $field->update( a => $value );
            }
        }
        ($authid) = AddAuthority($legacy, $authid, $authtypecode);
    }

    $authid = 0 unless $authid;
    $self->log->notice(
        ( $auth
          ? __x("  * Replace {authid}", authid => $authid)
          : __x("  * Add {authid}", authid => $authid)
        )
        . "\n" );
    $self->log->debug( "\n" );


    # On cherche un 035 avec $9 sudoc qui indique une fusion d'autorité Sudoc
    # 035$a contient le PPN de la notice qui a été fusionnée avec la notice en
    # cours de traitement.  On retrouve les notices biblio Koha liées à
    # l'ancienne autorité et on les modifie pour qu'elle pointent sur la
    # nouvelle autorité.
    for my $field ( $record->field('035') ) {
        my $sudoc = $field->subfield('9');
        next unless $sudoc && $sudoc =~ /sudoc/i;
        my $obsolete_ppn = $field->subfield('a');
        my ($obsolete_authid, $auth) =
            $self->sudoc->koha->get_auth_by_ppn($obsolete_ppn);
        next unless $auth;
        $self->log->notice(
          __x("  Sudoc merging with this authority of obsolete authority (PPN {obsolete_ppn}, authid {obsolete_authid})",
              obsolete_ppn => $obsolete_ppn, obsolete_authid => $obsolete_authid) . "\n" );
        my @modified_biblios;
        for ( $self->sudoc->koha->get_biblios_by_authid($obsolete_authid) ) {
            my ($biblionumber, $framework, $modif) = @$_;
            my $found = 0;
            for my $field ( $modif->field("[4-7]..") ) {
                $field->subf( [ map {
                    my ($letter, $value) = @$_;
                    if ( $letter eq '3' && $value eq $obsolete_ppn ) {
                        $value = $ppn;
                    }
                    elsif ( $letter eq '9' && $value eq $obsolete_authid ) {
                        $found = 1;
                        $value = $authid;
                    }
                    [ $letter, $value ];
                } @{$field->subf} ] );
            }
            if ( $found ) {
                push @modified_biblios, $biblionumber;
                $modif->delete('995');
                $self->log->debug( $modif->as('Text') );
                ModBiblio($modif->as('Legacy'), $biblionumber, $framework)
                    if $self->doit;
            }
        }
        if ( @modified_biblios ) {
            $self->log->notice(
                __x("  Linked biblios modified: "),
                join(', ', @modified_biblios), "\n" );
        }
    } 

}

1;
