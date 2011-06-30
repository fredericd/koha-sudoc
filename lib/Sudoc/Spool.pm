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

package Sudoc::Spool;
use Moose;

use File::Copy;
use YAML;


# Le répertoire du spool des fichiers traités par le chargeur Sudoc,
# ainsi que ses sous-répertoires. Les fichiers arrivent de l'ABES dans le
# répertoire 'staged'. Puis quand ils sont entièrement téléchargés, ils
# sont déplacés en 'waiting'. De là, ils sont chargés un à un dans Koha.
# Après chargement, ils sont déplacés en 'done'.
my $spool_dir   = 'var/spool';
my $staged_dir  = 'staged';
my $waiting_dir = 'waiting';
my $done_dir    = 'done';

# Moulinette SUDOC
has sudoc => ( is => 'rw', isa => 'Sudoc', required => 1 );


sub _sortable_name {
    my $name = shift;
    if ( $name =~ /^TR(\d*)R(\d*)([A-C])(.*)$/ ) {
        my $letter = $3 eq 'A' ? 'B' :
                     $3 eq 'B' ? 'A' : $3;
        $name = sprintf("TR%05dR%05d", $1, $2) . $letter . $4;
    }
    return $name;
}


# Retourne les fichiers d'une categorie (staged/waiting/done) et d'un
# type donnée. Par ex: 
# $files = $spool->file('waiting', 'c');
# $files = $spool->file('done', '[a|b]');
sub files {
    my ($self, $where, $type) = @_;
    my $subdir =
        $where =~ /staged/i  ? $staged_dir :
        $where =~ /waiting/i ? $waiting_dir : $done_dir;
    my $dir = $self->sudoc->sudoc_root . "/$spool_dir/" .
              $self->sudoc->iln . "/$subdir";
    opendir(my $hdir, $dir) || die "Impossible d'ouvrir $dir: $!";
    [ sort { _sortable_name($a) cmp _sortable_name($b) }
        grep { /$type\d{3}.raw$/i } readdir($hdir) ];
}


# Retourne le premier lot de fichiers d'une catégorie et d'un type donnée
sub first_batch_files {
    my ($self, $where, $type) = @_;

    my $files = $self->files($where, $type);
    return $files unless @$files;

    my ($prefix_first) = $files->[0] =~ /^(.*)001.RAW/;
    my @first_files;
    for my $file (@$files) {
        my ($prefix) = $file =~ /^(.*)\d{3}.RAW/;
        last if $prefix ne $prefix_first;
        push @first_files, $file;
    }
    return \@first_files;
}


# Retourne la pathname d'un fichier qu'on retrouve, dans l'ordre, soit
# dans le spool 'waiting' soit dans le spool 'done'. Si le fichier
# n'existe pas, retourne undef.
sub file_path {
    my ($self, $name) = @_;
    
    my $path = $self->sudoc->sudoc_root . "/$spool_dir/" .
               $self->sudoc->iln . "/$waiting_dir/$name";
    return $path if -f $path;

    $path = $self->sudoc->sudoc_root . "/$spool_dir/" .
            $self->sudoc->iln . "/$done_dir/$name";
    return $path if -f $path;

    return;
}


# Déplace un fichier dans le spool 'done'
sub move_done {
    my ($self, $name) = @_;
    my $path = $self->sudoc->sudoc_root . "/$spool_dir/" .
               $self->sudoc->iln . "/$waiting_dir/$name";
    return unless -f $path;
    my $target = $self->sudoc->sudoc_root . "/$spool_dir/" .
                 $self->sudoc->iln . "/$done_dir/$name";
    move($path, $target);   
}


# Déplace tous les fichiers de l'ILN courant de staged dans waiting
sub staged_to_waiting {
    my $self = shift;
    
    my $staged = $self->sudoc->sudoc_root . "/$spool_dir/" .
                 $self->sudoc->iln . "/$staged_dir";
    my $target = $self->sudoc->sudoc_root . "/$spool_dir/" .
                 $self->sudoc->iln . "/$waiting_dir";
    opendir(my $hdir, $staged) || die "Impossible d'ouvrir $staged: $!";
    my @files = sort grep { not /^\./ } readdir($hdir);
    for my $file (@files) {
        move("$staged/$file", $target);
    }
}


# Crée les sous-répertoires d'un ILN, s'ils n'existent pas déjà
sub init_iln {
    my ($self, $iln) = @_;

    my $dir = $self->sudoc->sudoc_root . "/$spool_dir/$iln";
    return if -d $dir;

    mkdir $dir;
    mkdir "$dir/$staged_dir";
    mkdir "$dir/$waiting_dir";
    mkdir "$dir/$done_dir";
}


1;
