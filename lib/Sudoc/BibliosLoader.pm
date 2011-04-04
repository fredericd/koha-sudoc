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

package Sudoc::BibliosLoader;
use Moose;

use FindBin qw( $Bin );
use lib "$Bin/../lib";

use C4::Biblio;
use C4::Items;
use C4::AuthoritiesMarc;
use MARC::Moose::Field::Control;
use MARC::Moose::Reader::File::Iso2709;
use Sudoc::Converter;
use Log::Dispatch;
use Log::Dispatch::Screen;
use Log::Dispatch::File;
use YAML;


# Moulinette SUDOC
has sudoc => ( is => 'rw', isa => 'Sudoc', required => 1 );

# Fichier des notices biblio
has file => ( is => 'rw', isa => 'Str', required => 1 );

# Chargement effectif ?
has doit => ( is => 'rw', isa => 'Bool', default => 0 );

# Compteur d'enregistrements traités
has count => (  is => 'rw', isa => 'Int', default => 0 );

# Compteur d'enregistrements remplacés
has count_replaced => (  is => 'rw', isa => 'Int', default => 0 );

# Converter
has converter => (
    is      => 'rw',
    isa     => 'Sudoc::Converter',
);


my $log = Log::Dispatch->new();


sub BUILD {
    my $self = shift;

    $log->add( Log::Dispatch::Screen->new(
        name      => 'screen',
        min_level => 'notice',
    ) );
    $log->add( Log::Dispatch::File->new(
        name      => 'file1',
        min_level => 'debug',
        filename  => $self->sudoc->sudoc_root . '/var/log/' .
                     $self->sudoc->iln . '-biblios.log',
        mode      => '>>',
    ) );

    # Instanciation du converter
    my $converter = $self->sudoc->c->{$self->sudoc->iln}->{biblio}->{converter};
    my $class = 'Sudoc::Converter';
    $class .= "::$converter" if $converter;
    unless ( eval "use $class" ) {
        $log->warning(
            "Attention : le converter $converter n'est pas défini. " .
            "On utilise le converter par défaut\n" );
        $class = 'Sudoc::Converter';
    }
    $converter = $class->new( sudoc => $self->sudoc );
    $self->converter( $converter );
}


sub handle_record {
    my ($self, $record) = @_;

    # FIXME Reset de la connexion tous les x enregistrements
    $self->sudoc->koha->zconn_reset()  unless $self->count % 100;

    my $ppn = $record->field('001')->value;
    my $conf = $self->sudoc->c->{$self->sudoc->iln}->{biblio};
    $log->notice( "Notice #" . $self->count . " PPN $ppn\n" );
    $log->debug( $record->as('Text') );

    # On déplace le PPN
    $self->sudoc->ppn_move($record, $conf->{ppn_move});

    # On cherche si la notice entrante ne se trouve pas déjà dans le catalogue Koha.
    my ($biblionumber, $framework, $koha_record);
    ($biblionumber, $framework, $koha_record) =
        $self->sudoc->koha->get_biblio_by_ppn( $ppn );
    if ($koha_record) {
        $log->debug("  PPN trouvé dans la notice Koha $biblionumber\n" );
    }
    else {
        # On cherche un 035 avec $9 sudoc qui indique une fusion de notices Sudoc 035$a
        # contient le PPN de la notice qui a été fusionnée avec la notice en cours de
        # traitement.
        for my $field ( $record->field('035') ) {
            my $sudoc = $field->subfield('9');
            next unless $sudoc && $sudoc =~ /sudoc/i;
            my $ppn_doublon = $field->subfield('a');
            ($biblionumber, $framework, $koha_record) =
                $self->sudoc->koha->get_biblio_by_ppn( $ppn_doublon );
            if ($koha_record) {
                $log->notice(
                  "  Fusion Sudoc du PPN $ppn_doublon de la notice Koha " .
                  "$biblionumber\n" );
                last;
            }
        } 
    }
    unless ($koha_record) {
        # On cherche un 035 avec un $5 contenant un RCR de l'ILN, auquel cas $a contient
        # le biblionumber d'une notice Koha
        my $rcr_hash = $self->sudoc->c->{ $self->sudoc->iln }->{rcr};
        for my $field ( $record->field('035') ) {
            my $rcr = $field->subfield('5');
            next unless $rcr && $rcr_hash->{$rcr};
            next unless $biblionumber = $field->subfield('a');
            ($framework, $koha_record) =
                $self->sudoc->koha->get_biblio( $biblionumber );
            if ($koha_record) {
                $log->notice(
                  "  Fusion avec la notice Koha $biblionumber trouvée en 035\$a " .
                  "pour le RCR $rcr\n");
                last;
            }
        } 
    }

    $self->converter->authoritize( $record );

    if ( $koha_record ) {
        # Modification d'une notice
        $log->debug("  Notice après traitements :\n" . $record->as('Text') );
        $log->notice("  * Remplace $biblionumber\n" );
        $self->converter->merge($record, $koha_record);
        ModBiblio($record->as('Legacy'), $biblionumber, $framework)
            if $self->doit;
    }
    else {
        # Nouvelle notice
        $self->converter->itemize($record);
        $self->converter->clear($record);
        $log->debug("  Notice après traitements :\n" . $record->as('Text') );
        $log->notice("  * Ajout\n" );
        $framework = $self->sudoc->c->{$self->sudoc->iln}->{biblio}->{framework};
        if ( $self->doit ) {
            my $marc = $record->as('Legacy');
            my ($biblionumber, $biblioitemnumber) =
                AddBiblio($marc, $framework, { defer_marc_save => 1 });
            my ($itemnumbers_ref, $errors_ref) =
                AddItemBatchFromMarc($marc, $biblionumber, $biblioitemnumber, '' );
        }
    }
    $log->debug("\n");
}


sub run {
    my $self = shift;

    $log->notice("Chargement du fichier de notices biblio : " . $self->file . "\n");
    $log->notice("** Test **\n") unless $self->doit;
    my $reader = MARC::Moose::Reader::File::Iso2709->new(
        file => $self->sudoc->spool->file_path( $self->file ) );
    while ( my $record = $reader->read() ) {
        $self->count( $self->count + 1 );
        $self->handle_record($record);
    }
    if ( $self->doit ) {
        $log->notice( "Notices chargées : " . $self->count . ", dont " .
            $self->count_replaced . " remplacées\n" );
        $self->sudoc->spool->move_done($self->file);
    }
    else {
        $log->notice(
            "** Test ** Le fichier " . $self->file . " n'a pas été chargé\n" );
    }
}


1;
