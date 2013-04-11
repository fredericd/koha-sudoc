# Copyright (C) 2012 Tamil s.a.r.l. - http://www.tamil.fr
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
use 5.010;
use utf8;

use C4::Items;
use YAML;
use Encode;
use Business::ISBN;
use List::Util qw/first/;

with 'MooseX::RW::Writer::File';

# Moulinette SUDOC
has sudoc => ( is => 'rw', isa => 'Sudoc', required => 1 );

# Sortie Date-Auteur-Titre plutôt qu'ISBN
has dat => ( is => 'rw', isa => 'Bool', default => 0 );

# Où placer la cote Koha dans la notice ABES, par défaut 930 $a
has coteabes => (
    is => 'rw',
    isa => 'Str',
    default => '930 $a'
);

# Test de recouvrement (on sort moins d'info)
has test => ( is => 'rw', isa => 'Bool', default => 1 );

# Nombre max de lignes par fichier
has lines => ( is => 'rw', isa => 'Int', default => 1000 );

# Disponibilité pour le PEB ?
has peb => ( is => 'rw', isa => 'Bool', default => 1 );


#
# Les fichiers par RCR, avec branch Koha correspondante. Les info proviennent
# du fichier de conf sudoc.conf et sont construites à l'instantiation de
# l'objet.
# Par exemple :
# {
#   BIB1 => {
#     branch => 'BIB1',         
#     rcr    => '1255872545',  # RCR correspondant à la biblio Koha
#     key    => {
#        cle1 => [ [biblionumber1, cote1],  [biblionumber2, cote2], ... ],
#        cle2 => [ [
#     },
#     line   => 123,           # N° de ligne dans le fichier courant
#     index  => 2,             # Index du ficier (fichier.index)
#   },
#   BIB2 => {
#     ...
# }
#   
has loc => (
    is => 'rw',
    isa => 'HashRef',
    default => sub {
        my $self = shift;
        my %loc;
        my $hbranch = $self->sudoc->c->{$self->sudoc->iln}->{branch};
        while ( my ($branch, $rcr) = each %$hbranch ) {
            $loc{$branch} = {
                branch => $branch,
                rcr    => $rcr,
                key    => {},
            };
        }
        $self->loc( \%loc );
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


sub write_isbn {
    my ($self, $record) = @_;

    my @isbns = $record->field('010');
    return unless @isbns;

    my $biblionumber = $self->sudoc->koha->get_biblionumber($record);
    my $items = GetItemsByBiblioitemnumber($biblionumber);
    for my $isbn ( @isbns ) {
        $isbn = $isbn->subfield('a');
        next unless $isbn;
        # Si c'est un EAN, on convertit en ISBN...
        if ( $isbn =~ /^978/ ) {
            if ( my $i = Business::ISBN->new($isbn) ) {
                if ( $i = $i->as_isbn10 ) {
                    $isbn = $i->as_string;
                }
            }
        }
        $isbn =~ s/ //g;
        $isbn =~ s/-//g;
        # On nettoie les ISBN de la forme 122JX(vol1)
        $isbn = $1 if $isbn =~ /(.*)\(/;
        next unless $isbn;
        for my $ex ( @$items ) {
            my $branch = $ex->{homebranch};
            my $loc = $self->loc->{$branch};
            next unless $loc;
            my $key = $loc->{key};
            my $cote = $ex->{itemcallnumber} || '';
            $cote =~ s/;//g;
            my $bibcote = $key->{$isbn} ||= [];
            # On ne prend pas les doublons d'ISBN pour un même biblionumber
            next if first { $_->[0] eq $biblionumber; } @$bibcote;
            push @$bibcote, [$biblionumber, $cote];
            last;
        }
    }
}


sub _clean_string {
    my $value = shift;

    # Suppression des accents, passage en minuscule
    $value = decode('UTF-8', $value) unless utf8::is_utf8($value);
    $value = lc $value;
    $value =~ y/âàáäçéèêëïîíôöóøùûüñčć°/aaaaceeeeiiioooouuuncco/;

    $value =~ s/;/ /g;
    $value =~ s/,/ /g;
    $value =~ s/"/ /g;
    $value =~ s/\?/ /g;
    $value =~ s/!/ /g;
    $value =~ s/'/ /g;
    $value =~ s/\'/ /g;
    $value =~ s/\)/ /g;
    $value =~ s/\(/ /g;
    $value =~ s/\]/ /g;
    $value =~ s/\[/ /g;
    $value =~ s/:/ /g;
    $value =~ s/=/ /g;
    $value =~ s/-/ /g;
    $value =~ s/\x{0088}/ /g;
    $value =~ s/\x{0089}/ /g;
    $value =~ s/\x{0098}/ /g;
    $value =~ s/\x{0099}/ /g;
    $value =~ s/\x9c/ /g;
    $value =~ s/\./ /g;

    while ( $value =~ s/  / / ) { ; }

    return $value;
}


sub write_dat {
    my ($self, $record) = @_;

    my $date = $record->field('210');
    return unless $date;
    $date = $date->subfield('d') || '';
    return unless $date =~ /(\d{4})/;
    $date = $1;

    my $auteur;
    for my $tag ( qw( 700 701 702 710 711 712 ) ) {
        $auteur = $record->field($tag);
        next unless $auteur;
        $auteur = $auteur->subfield('a') || '';
        $auteur = _clean_string($auteur);
        last if $auteur;
    }
    $auteur ||= '';

    # Traitement du titre
    my $titre = $record->field('200') || '';
    $titre = $titre->subfield('a') || '' if $titre;

    # Suppression des accents, passage en minuscule
    $titre = _clean_string($titre);

    # Les mots vides
    for my $word ( @stopwords ) {
        $titre =~ s/\b$word\b/ /gi;
    }

    while ( $titre =~ s/  / / ) { ; }
    $titre =~ s/^ *//;
    $titre =~ s/ *$//;
    
    my $dat = "$date;$auteur;$titre";
    my $biblionumber = $self->sudoc->koha->get_biblionumber($record);
    my $items = GetItemsByBiblioitemnumber($biblionumber);
    for my $ex ( @$items ) {
        my $branch = $ex->{homebranch};
        my $loc = $self->loc->{$branch};
        next unless $loc;
        my $key = $loc->{key};
        my $cote = $ex->{itemcallnumber} || '';
        $key->{$dat} ||= [];
        push @{$key->{$dat}}, [$biblionumber, $cote];
        last;
    }

}


sub write_to_file {
    my $self = shift;

    my $max_lines = $self->lines;
    my $prefix = $self->dat ? 'r' : 'i';
    for my $loc ( values %{$self->loc} ) {
        my $fh;
        open my $fh_mult, ">:encoding(utf8)",
          $prefix . $loc->{rcr} . ( $self->peb ? 'u' : 'g' ) . "_clemult.txt";
        $loc->{index} = 0;
        $loc->{line} = 99999999;
        for my $key ( sort keys %{$loc->{key}} ) {
            my @bncote = @{$loc->{key}->{$key}};
            if ( @bncote == 1 ) {
                if ( $loc->{line} >= $self->lines ) {
                    $loc->{index}++;
                    my $name = $prefix . $loc->{rcr} .
                               ( $self->peb ? 'u' : 'g' ) .
                               '_' .
                               sprintf("%04d", $loc->{index}) . '.txt';
                    close($fh) if $fh;
                    open $fh, ">:encoding(utf8)", $name;
                    print $fh
                        $self->dat ? 'date;auteur;titre' : 'ISBN',
                        ';',
                        $self->coteabes,
                        ';L035 $a', "\n";
                    $loc->{line} = 1;
                }
                if ( $self->test ) {
                    print $fh "$key\n";
                }
                else {
                    my ($biblionumber, $cote) = @{$bncote[0]};
                    print $fh "$key;$cote;$biblionumber\n"
                }
                $loc->{line}++;
            }
            else {
                print $fh_mult
                  "$key\n  ",
                  join("\n  ", map { $_->[0] . " " . $_->[1] } @bncote), "\n";
            }
        }
    }
}


sub write {
    my ($self, $record) = @_;

    # S'il la notice contient déjà un PPN, inutile de la traiter
    return if $record->field('009');

    $self->count( $self->count + 1);

    $self->dat ? $self->write_dat($record) : $self->write_isbn($record);
}

1;
