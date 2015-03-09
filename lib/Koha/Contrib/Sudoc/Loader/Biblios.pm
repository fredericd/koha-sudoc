# Copyright (C) 2015 Tamil s.a.r.l. - http://www.tamil.fr
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

package Koha::Contrib::Sudoc::Loader::Biblios;
use Moose;

extends 'Koha::Contrib::Sudoc::Loader';

use Modern::Perl;
use YAML;
use Locale::Messages;



# On cherche les notices doublons SUDOC. On renvoie la liste des notices
# Koha correspondantes.
sub doublons_sudoc {
    my ($self, $record) = @_;
    my @doublons;
    # On cherche un 035 avec $9 sudoc qui indique une fusion de notices Sudoc 035$a
    # contient le PPN de la notice qui a été fusionnée avec la notice en cours de
    # traitement.
    for my $field ( $record->field('035') ) {
        my $sudoc = $field->subfield('9');
        next unless $sudoc && $sudoc =~ /sudoc/i;
        my $ppn = $field->subfield('a');
        my ($biblionumber, $framework, $koha_record) =
            $self->sudoc->koha->get_biblio_by_ppn( $ppn );
        if ($koha_record) {
            $self->log->notice("  Fusion Sudoc du PPN $ppn avec le biblionumber Koha $biblionumber\n");
            push @doublons, {
                ppn          => $ppn,
                record       => $koha_record,
                biblionumber => $biblionumber,
                framework    => $framework,
            };
        }
    } 
    return \@doublons;
}


sub handle_record {
    my ($self, $record) = @_;

    # FIXME: Ici et pas en-tête parce qu'il faut que l'environnement Shell soit
    # déjà fixé avant de charger ces modules qui ont besoin de KOHA_CONF et qui
    # le garde
    use C4::Biblio;
    use C4::Items;

    # FIXME Reset de la connexion tous les x enregistrements
    $self->sudoc->koha->zconn_reset()  unless $self->count % 10;

    my $ppn = $record->field('001')->value;
    $self->log->notice("Notice #" . $self->count . " PPN $ppn\n");
    $self->log->debug( $record->as('Text') );

    # On déplace le PPN
    $self->sudoc->ppn_move($record, $self->sudoc->c->{biblio}->{ppn_move});

    # Est-ce qu'il faut passer la notice ?
    if ( $self->converter->skip($record) ) {
        $record = undef;
        $self->count_skipped( $self->count_skipped + 1 );
        $self->log->notice( "  * Ignorée\n" );
        return;
    }

    # On cherche si la notice entrante ne se trouve pas déjà dans le
    # catalogue Koha.
    my ($biblionumber, $framework, $koha_record);
    ($biblionumber, $framework, $koha_record) =
        $self->sudoc->koha->get_biblio_by_ppn( $ppn );
    if ($koha_record) {
        $self->log->debug("  PPN trouvé dans la notice Koha $biblionumber");
    }
    else {
        # On cherche un 035 avec un $5 contenant un RCR de l'ILN, auquel cas $a contient
        # le biblionumber d'une notice Koha
        my $rcr_hash = $self->sudoc->c->{rcr};
        for my $field ( $record->field('035') ) {
            my $rcr = $field->subfield('5');
            next unless $rcr && $rcr_hash->{$rcr};
            next unless $biblionumber = $field->subfield('a');
            ($framework, $koha_record) =
                $self->sudoc->koha->get_biblio( $biblionumber );
            if ($koha_record) {
                $self->log->notice(
                  "  Fusion de la notice Koha $biblionumber trouvée en 035\$a " .
                  "pour le RCR $rcr\n" );
                last;
            }
        } 
    }

    # Les doublons SUDOC. Il n'y a qu'un seul cas où on peut en faire
    # quelque chose. Si on a déjà trouvé une notice Koha ci-dessus, on
    # ne peut rien faire : en effet, on a déjà une cible pour fusionner
    # la notice entrante. S'il y a plus d'un doublon qui correspond à
    # des notices Koha, on ne sait à quelle notice Koha fusionner la
    # notice entrante.
    my $doublons = $self->doublons_sudoc($record);
    if ( @$doublons ) {
        if ( $koha_record || @$doublons > 1 ) {
            $self->log->warning(
                "  Attention ! la notice entrante doit être fusionnées à plusieurs notices " .
                  "Koha existantes. À FAIRE MANUELLEMENT\n" );
        }
        else {
            # On fusionne le doublon SUDOC (unique) avec la notice SUDOC entrante
            my $d = shift @$doublons;
            ($biblionumber, $framework, $koha_record) =
                ($d->{biblionumber}, $d->{framework}, $d->{record});
        }
    }

    $self->converter->init( $record );
    $self->converter->authoritize( $record );
    $self->converter->linking( $record );

    if ( $koha_record ) {
        # Modification d'une notice
        $self->count_replaced( $self->count_replaced + 1 );
        $self->converter->merge($record, $koha_record);
        $self->converter->clean($record);
        $self->log->debug(
            "  Notice après traitement :\n" . $record->as('Text') );
        $self->log->notice("  * Remplace $biblionumber\n" );
        ModBiblio($record->as('Legacy'), $biblionumber, $framework)
            if $self->doit;
    }
    else {
        # Nouvelle notice
        $self->count_added( $self->count_added + 1 );
        $self->converter->itemize($record);
        $self->converter->clean($record);
        $self->log->debug(
            "  Notice après traitement :\n" . $record->as('Text') );
        $self->log->notice( "  * Ajout\n" );
        $framework = $self->converter->framework($record);
        if ( $self->doit ) {
            my $marc = $record->as('Legacy');
            my ($biblionumber, $biblioitemnumber) =
                AddBiblio($marc, $framework, { defer_marc_save => 1 });
            my ($itemnumbers_ref, $errors_ref) =
                AddItemBatchFromMarc($marc, $biblionumber, $biblioitemnumber, $framework);
            $self->log->warning( "erreur pendant l'ajout de l'exemplaire :\n" . Dump($errors_ref) )
                if @$errors_ref;
            C4::Biblio::_strip_item_fields($marc, $framework);
            ModBiblioMarc($marc, $biblionumber, $framework);
        }
    }
    $self->log->debug("\n");
}


1;