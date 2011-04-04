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

package Sudoc::AuthoritiesLoader;
use Moose;

use C4::Context;
use C4::AuthoritiesMarc;
use MARC::Moose::Record;
use MARC::Moose::Reader::File::Iso2709;
use Log::Dispatch;
use Log::Dispatch::Screen;
use Log::Dispatch::File;
use YAML;


# Moulinette SUDOC
has sudoc => ( is => 'rw', isa => 'Sudoc', required => 1 );

# Fichier d'autorités
has file => ( is => 'rw', isa => 'Str', required => 1 );

# Chargement effectif ?
has doit => ( is => 'rw', isa => 'Bool', default => 0 );

# Compteur d'enregistrements traités
has count => (  is => 'rw', isa => 'Int', default => 0 );

# Compteur d'enregistrements remplacés
has count_replaced => (  is => 'rw', isa => 'Int', default => 0 );

# Le logger
has log => (
    is => 'rw',
    isa => 'Log::Dispatch',
    default => sub { Log::Dispatch->new() },
);



sub BUILD {
    my $self = shift;
    $self->log->add( Log::Dispatch::Screen->new(
        name      => 'screen',
        min_level => 'notice',
    ) );
    $self->log->add( Log::Dispatch::File->new(
        name      => 'file1',
        min_level => 'debug',
        filename  => $self->sudoc->sudoc_root . '/var/log/' .
                     $self->sudoc->iln . '-authorities.log',
        mode      => '>>',
    ) );
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

    # On cherche un 035 avec $9 sudoc qui indique une fusion de notices Sudoc
    # 035$a contient le PPN de la notice qui a été fusionnée avec la notice en cours de
    # traitement.
    my ($authid, $auth);
    for my $field ( $record->field('035') ) {
        my $sudoc = $field->subfield('9');
        next unless $sudoc && $sudoc =~ /sudoc/i;
        my $ppn_doublon = $field->subfield('a');
        print "ppn doublon: $ppn_doublon\n";
        ($authid, $auth) =
            $self->sudoc->koha->get_auth_by_ppn( $ppn_doublon );
        if ($auth) {
            $self->log->notice(
              "  PPN $ppn fusion Sudoc du PPN $ppn_doublon de la notice Koha " .
              "$authid\n" );
            last;
        }
    } 

    # Y a-t-il déjà dans la base Koha une authorité ayant ce PPN ?
    unless ($authid) {
        ($authid, $auth) = $self->sudoc->koha->get_auth_by_ppn($ppn);
        if ( $auth ) {
            $record->append(
                MARC::Moose::Field::Control->new( tag => '001', value => $authid) );
            $self->count_replaced( $self->count_replaced + 1 );
        }
    }

    ($authid) = AddAuthority($record->as('Legacy'), $authid, $authtypecode)
        if $self->doit;
    $authid = 0 unless $authid;
    $self->log->notice(
        ($auth ? "  * Remplace" : "  * Ajout") .
        " authid $authid\n" );
}


sub run {
    my $self = shift;

    $self->log->notice("Chargement du fichier d'autorités : " . $self->file . "\n");
    $self->log->notice("** Test **\n") unless $self->doit;
    my $reader = MARC::Moose::Reader::File::Iso2709->new(
        file => $self->sudoc->spool->file_path( $self->file ) );
    while ( my $record = $reader->read() ) {
        $self->count( $self->count + 1 );
        $self->handle_record($record);
    }
    $self->log->notice( "Notices chargées : " . $self->count . ", dont " .
                  $self->count_replaced . " remplacées\n" );

    if ( $self->doit) {
        $self->sudoc->spool->move_done($self->file);
    }
    else {
        $self->log->notice(
            "** Test ** Le fichier " . $self->file . " n'a pas été chargé\n" );
    }
}

1;
