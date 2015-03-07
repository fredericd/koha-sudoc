#!/usr/bin/perl 

package Koha::Contrib::Sudoc::TransferDaemon;
use Moose;

use Modern::Perl;
use AnyEvent;
use Mail::Box::Manager;
use DateTime;
use Koha::Contrib::Sudoc;


has sudoc => ( is => 'rw', isa => 'Sudoc', default => sub { Koha::Contrib::Sudoc->new } );

has mgr => (
    is => 'rw',
    isa => 'Mail::Box::Manager',
    default => sub { Mail::Box::Manager->new },
);

has verbose => ( is => 'rw', isa => 'Bool', default => 0 );


# Global
my $daemon_id = 'sudoc-trans';


sub BUILD {
    my $self = shift;

    say "Starting ABES transfer daemon";

    my $timeout = $self->sudoc->c->{trans}->{timeout};
    my $idle = AnyEvent->timer(
        after    => $timeout,
        interval => $timeout,
        cb       => sub { $self->transfert_abes(); }
    );
    AnyEvent->condvar->recv;
}


sub send_gtd {
    my ($self, $msg_abes) = @_;

    # Récupération dans le courriel de l'ABES des info dont a besoin
    # pour construire la réponse
    my $body = $msg_abes->body;
    my ($jobid) = $body =~ /JobId\s*:\s*(\d*)/;
    my ($iln)   = $body =~ /\/iln(\d*)\//;

    # La date
    my $year = DateTime->now->year;

    say "Send GTD: ILN $iln, job $jobid, year $year";

    my $conf = $self->sudoc->c->{trans};

    my $head = Mail::Message::Head->new;
    $head->add( From => $conf->{email}->{koha} );
    $head->add( To => $conf->{email}->{abes} );
    $head->add( Subject => 'GET TITLE DATA' );

    $body = Mail::Message::Body::Lines->new(
        data =>
            "GTD_ILN = $iln\n" .
            "GTD_YEAR = $year\n" .
            "GTD_FILE_TO = " . $conf->{ftp_host} . "\n" .
            "GTD_ORDER = TR$jobid*\n" .
            "GTD_REMOTE_DIR = spool/$iln/staged\n",
    );

    my $message = Mail::Message->new(
        head => $head,
        body => $body );
    $message->send;
}


sub move_to_waiting {
    my ($self, $msg) = @_;

    my $body = $msg->body;
    my ($iln) = $body =~ /GTD_ILN\s*=\s*(\d*)/i;
 
    say "End file transfer from ABES for ILN $iln";

    my $sudoc = $self->sudoc;
    $sudoc->iln($iln);
    $sudoc->spool->staged_to_waiting();
}


sub transfert_abes {
    my $self = shift;

    # Ne rien faire si la MBOX est vide
    my $mbox = $self->sudoc->c->{trans}->{mbox};
    return unless -f $mbox;

    my $folder = $self->mgr->open( folder => $mbox, access => 'rw' );
    for my $message ($folder->messages) {
        given ($message->subject()) {
            when ( /status is 9/ ) { $self->send_gtd( $message ); }
            when ( /status: 0/ ) { $self->move_to_waiting( $message ); }
        }
        $message->delete;
    }
    $folder->close;
}

1;
