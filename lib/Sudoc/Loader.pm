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

package Sudoc::Loader;
use Moose;

use FindBin qw( $Bin );
use lib "$Bin/../lib";

use MARC::Moose::Reader::File::Iso2709;
use Sudoc::Converter;
use Log::Dispatch;
use Log::Dispatch::Screen;
use Log::Dispatch::File;
use YAML;
use Try::Tiny;
use Locale::TextDomain 'fr.tamil.sudoc';


# Moulinette SUDOC
has sudoc => ( is => 'rw', isa => 'Sudoc', required => 1 );

# Fichier des notices biblios/autorités
has file => ( is => 'rw', isa => 'Str', required => 1 );

# Chargement effectif ?
has doit => ( is => 'rw', isa => 'Bool', default => 0 );

# Compteur d'enregistrements traités
has count => (  is => 'rw', isa => 'Int', default => 0 );

# Compteur d'enregistrements ajoutés
has count_added => (  is => 'rw', isa => 'Int', default => 0 );

# Compteur d'enregistrements remplacés
has count_replaced => (  is => 'rw', isa => 'Int', default => 0 );

# Compteur d'enregistrements non traités
has count_skipped => ( is => 'rw', isa => 'Int', default => 0 );

# Converter
has converter => (
    is      => 'rw',
    isa     => 'Sudoc::Converter',
);

# Le logger
has log => (
    is => 'rw',
    isa => 'Log::Dispatch',
    default => sub { Log::Dispatch->new() },
);


sub BUILD {
    my $self = shift;

    my $id = ref($self);
    ($id) = $id =~ /.*:(.*)$/;
    $self->log->add( Log::Dispatch::Screen->new(
        name      => 'screen',
        min_level => 'notice',
    ) );
    $self->log->add( Log::Dispatch::File->new(
        name      => 'file1',
        min_level => 'debug',
        filename  => $self->sudoc->sudoc_root . '/var/log/' .
                     $self->sudoc->iln . "-$id.log",
        mode      => '>>',
    ) );

    # Instanciation du converter
    my $converter = $self->sudoc->c->{$self->sudoc->iln}->{biblio}->{converter};
    my $class = 'Sudoc::Converter';
    $class .= "::$converter" if $converter;
    try {
        Class::MOP::load_class($class);
    } catch {
        $self->log->warning(
            __x("Warning: converter {converter} isn't defined. " .
                "Default converter will be used.",
                converter => $converter) .
            "\n" );
        $class = 'Sudoc::Converter';
    };
    $converter = $class->new( sudoc => $self->sudoc );
    $self->converter( $converter );
}


sub handle_record {
    my ($self, $record) = @_;
}


sub run {
    my $self = shift;

    $self->log->notice(
        __x("Loading file: {file}", file => $self->file) . "\n");
    $self->log->notice(__"** Test **" . "\n") unless $self->doit;
    my $reader = MARC::Moose::Reader::File::Iso2709->new(
        file => $self->sudoc->spool->file_path( $self->file ) );
    while ( my $record = $reader->read() ) {
        $self->count( $self->count + 1 );
        $self->handle_record($record);
    }
    
    $self->sudoc->spool->move_done($self->file)  if $self->doit;
    $self->log->notice(
        __nx("One record has been handled",
             "Number of record handled: {count}",
             $self->count,
             count => $self->count) .
        "\n" .
        __nx("One record has been added",
             "Number of record added: {count}",
             $self->count_added,
             count => $self->count_added) .
        "\n" .
        __nx("One record has been merged",
             "Number of merged records: {count}",
             $self->count_replaced,
             count => $self->count_replaced) .
        "\n" .
        __nx("One record has been skipped",
             "Number of skipped records: {count}",
             $self->count_skipped,
             count => $self->count_skipped) .
        "\n" );
    $self->log->notice(
        __x("** Test ** File {file} has not been loaded", file => $self->file) . "\n" )
        unless $self->doit;
}


1;
