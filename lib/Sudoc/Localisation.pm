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

package Sudoc::Localisation;
use Moose;

use YAML;

extends 'RecordWriter';

# Moulinette SUDOC
has sudoc => ( is => 'rw', isa => 'Sudoc', required => 1 );

# Sortie Date-Auteur-Titre plutôt qu'ISBN
has dat => ( is => 'rw', isa => 'Bool', default => 0 );

# Test de recouvrement (on sort moins d'info)
has test => ( is => 'rw', isa => 'Bool', default => 1 );

# Nombre max de lignes par fichier
has lines => ( is => 'rw', isa => 'Int', default => 1000 );

#
# Les fichiers par RCR, avec branch Koha correspondante. Les info proviennent
# du fichier de conf sudoc.conf et sont construites à l'instantiation de
# l'objet.
# Par exemple :
# {
#   BIB1 => {
#     branch => 'BIB1',         
#     rcr    => '1255872545',  # RCR correspondant à la biblio Koha
#     line   => 123,           # N° de ligne dans le fichier courant
#     index  => 2,             # Index du ficier (fichier.index)
#   },
#   BIB2 => {
#     ...
# }
#   
has fichier_rcr => (
    is => 'rw',
    isa => 'HashRef',
    default => sub {
        my $self = shift;
        my %fichier_rcr;
        while ( my ($branch, $rcr) = each %{$self->sudoc->c->{branch}} ) {
            $fichier_rcr{$branch} = {
                branch => $branch,
                rcr    => $rcr,
                line   => 9999,
                index  => 0,
            };
        }
        $self->fichier_rcr( \%fichier_rcr );
    },
);


sub get_file {
    my ($self, $branch, $prefix) = @_;
    my $file = $self->fichier_rcr->{$branch};
    return unless $file;
    my $line = $file->{line};
    $line++;
    my $fh = $file->{fh};
    if ( $line > $self->lines ) {
        my $index = $file->{index} + 1;
        my $name = $prefix . $file->{rcr} . 'u.' .
                   sprintf("%04d", $index);
        close($fh) if $fh;
        open $fh, ">$name";
        $file->{index} = $index;
        $file->{fh}    = $fh;
        $line = 1;
    }
    $file->{line} = $line;
    return $file;
}


sub write_isbn {
    my ($self, $record) = @_;

    my @isbns = $record->field('010');
    return unless @isbns;

    my $biblionumber = $record->field('090')->subfield('a');
    for my $isbn ( $record->field('010') ) {
        $isbn = $isbn->subfield('a');
        next unless $isbn;
        $isbn =~ s/ //g;
        $isbn =~ s/-//g;
        # On nettoie les ISBN de la forme 122JX(vol1)
        $isbn = $1 if $isbn =~ /(.*)\(/;
        next unless $isbn;
        for my $ex ( $record->field('995') ) {
            my $branch = $ex->subfield('b');
            my $file = $self->get_file($branch, 'i');
            next unless $file;
            my $cote = $ex->subfield('k') || '';
            my $fh = $file->{fh};
            if ( $self->test ) {
                print $fh "$isbn\n";
            }
            else {
                print $fh "$isbn;$cote;$biblionumber\n";
            }
        }
    }
}


sub write_dat {
    my ($self, $record) = @_;

    my $date = $record->field('210');
    return unless $date;
    $date = $date->subfield('d') || '';
    return unless $date =~ /(\d{4})/;
    $date = $1;

    my $auteur = $record->field('700') || '';
    $auteur = $auteur->subfield('a') || ''  if $auteur;

    my $titre = $record->field('200') || '';
    $titre = $titre->subfield('a') || '' if $titre;
    $titre =~ s/;/ /g;
    $titre =~ s/,/ /g;
    $titre =~ s/"/ /g;
    $titre =~ s/\?/ /g;
    $titre =~ s/!/ /g;
    $titre =~ s/'/ /g;
    $titre =~ s/\'/ /g;
    $titre =~ s/\)/ /g;
    $titre =~ s/\(/ /g;
    $titre =~ s/:/ /g;
    $titre =~ s/=/ /g;
    $titre =~ s/\./ /g;
    $titre =~ s/ or / /gi;
    $titre =~ s/ and / /gi;
    $titre =~ s/ not / /gi;
    $titre =~ s/ ou / /gi;
    $titre =~ s/ et / /gi;
    $titre =~ s/ sauf / /gi;
    while ( $titre =~ s/  / / ) { ; }
    $titre =~ s/^ *//;
    $titre =~ s/ *$//;
    $titre = lc $titre;
    
    my $dat = "$date;$auteur;$titre";
    my $biblionumber = $record->field('090')->subfield('a');
    for my $ex ( $record->field('995') ) {
        my $branch = $ex->subfield('b');
        my $file = $self->get_file($branch, 'r');
        next unless $file;
        my $cote = $ex->subfield('k') || '';
        my $fh = $file->{fh};
        if ( $self->test ) {
            print $fh "$dat\n";
        }
        else {
            print $fh "$dat;$cote;$biblionumber\n";
        }
    }

}


sub write {
    my ( $self, $record ) = @_;

    $self->SUPER::write();

    # S'il la notice contient déjà un PPN, inutile de la traiter
    return if $record->field('001');

    $self->dat ? $self->write_dat($record) : $self->write_isbn($record);
}

1;
