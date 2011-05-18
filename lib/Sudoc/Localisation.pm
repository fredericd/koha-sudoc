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
        my $hbranch = $self->sudoc->c->{$self->sudoc->iln}->{branch};
        while ( my ($branch, $rcr) = each %$hbranch ) {
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


# Listes de mots vides supprimés des titres/auteurs
# Cette liste est fournie par l'ABES
my @stopwords = qw(
per
org
mti
rec
isb
isn
ppn
dew
cla
msu
mee
cti
cot
lai
pai
rbc
res
the
prs
aut
num
tou
edi
sou
tir
bro
geo
mch
epn
tab
tco
dpn
sim
dup
vma
lva
pfm
mfm
pra
mra
kil
sel
col
nos
num
msa
cod
inl
cll
ati
nli
slo
rcr
typ
dep
spe
dom
reg
mno
mor
eta
nom
for
vil
dat
dac
dam
nrs
adr
apu
tdo
lan
pay
fct

a
ad
alla
am
at
aus
bei
cette
como
dalla
del
dem
des
dr
during
einem
es
fuer
i
impr
l
leur
mes
nel
o
over
por
r
ses
so
sur
this
under
vom
vous
with
ab
against
alle
among
atque
aussi
bis
ceux
cum
dans
dell
den
desde
du
e
einer
et
g
ihre
in
la
leurs
mit
no
oder
p
pour
s
sic
some
te
to
une
von
w
y
depuis
di
durant
ed
eines
f
gli
ihrer
into
las
lo
n
nos
of
par
qu
sans
since
sous
that
ueber
unless
vor
was
zu
der
die
durante
ein
el
for
h
il
its
le
los
nach
notre
on
per
quae
se
sive
st
the
um
unter
vos
we
zur
across
all
altre
asi
aupres
b
ce
comme
dall
degli
dello
deren
dont
durch
eine
en
from
his
im
j
les
m
ne
nous
ou
plus
que
selon
sn
sul
their
und
upon
votre
which
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
        my $name = $prefix . $file->{rcr} . 'u_' .
                   sprintf("%04d", $index) . '.txt';
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

    my $biblionumber = $self->sudoc->koha->get_biblionumber($record);
    for my $isbn ( @isbns ) {
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

    # Les mots vides
    for my $word ( @stopwords ) { $titre =~ s/ $word / /gi; }

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
    my ($self, $record) = @_;

    $self->SUPER::write();

    # S'il la notice contient déjà un PPN, inutile de la traiter
    #return if $record->field('001');

    $self->dat ? $self->write_dat($record) : $self->write_isbn($record);
}

1;
