package Koha::Contrib::Sudoc::TransferDaemon;
# ABSTRACT: Service de transfert de fichiers

use Moose;
use Modern::Perl;
use Mail::Box::Manager;
use DateTime;
use Path::Tiny;
use Log::Dispatch;
use Log::Dispatch::Screen;
use Log::Dispatch::Syslog;
use Koha::Contrib::Sudoc;


has sudoc => (
    is => 'rw',
    isa => 'Koha::Contrib::Sudoc',
    default => sub { Koha::Contrib::Sudoc->new }
);

has mgr => (
    is => 'rw',
    isa => 'Mail::Box::Manager',
    default => sub { Mail::Box::Manager->new },
);

has daemon_id => ( is => 'rw', isa => 'Str');

# Le logger
has log => (
    is => 'rw',
    isa => 'Log::Dispatch',
    default => sub { Log::Dispatch->new() },
);


# Global
my $daemon_id = 'sudoc-trans';


sub BUILD {
    my $self = shift;

    # On log à la fois à l'écran et dans syslog
    $self->log->add( Log::Dispatch::Screen->new(
        name      => 'screen',
        min_level => 'notice',
    ) );
    $self->log->add( Log::Dispatch::Syslog->new(
        name      => 'syslog',
        min_level => 'notice',
        ident     => $daemon_id . '-' . $self->sudoc->c->{iln}, 
        binmode   => ':encoding(utf8)',
    ) );

    $self->log->notice( "Démarrage du service de transfert ABES\n" );

    my $timeout = $self->sudoc->c->{trans}->{timeout} * 60;
    while (1) {
        $self->check_mbox();
        sleep($timeout);
    }
}


# Envoi à l'ABES d'un email GTD en réponse à un message 'status 9'. Celui-ci
# contient le numéro du job
sub ask_sending {
    my ($self, $msg) = @_;

    # Récupération dans le courriel de l'ABES des info dont on a besoin pour
    # construire la réponse
    my $body = $msg->body;
    my ($jobid) = $body =~ /JobId\s*:\s*(\d*)/;
    my ($iln)   = $body =~ /\/iln(\d*)\//;

    # La date
    my $year = DateTime->now->year;

    $self->log->notice(
        "Réception 'status 9'. Envoi GTD: ILN $iln, job $jobid, année $year\n" );

    my $c = $self->sudoc->c->{trans};

    my $head = Mail::Message::Head->new;
    $head->add( From => $c->{email}->{koha} );
    $head->add( To => $c->{email}->{abes} );
    $head->add( Subject => 'GET TITLE DATA' );

    $body = Mail::Message::Body::Lines->new(
        data =>
            "GTD_ILN = $iln\n" .
            "GTD_YEAR = $year\n" .
            "GTD_FILE_TO = " . $c->{ftp_host} . "\n" .
            "GTD_ORDER = TR$jobid*\n" .
            "GTD_REMOTE_DIR = staged\n",
    );

    my $message = Mail::Message->new(
        head => $head,
        body => $body );
    $message->send;
}


# La transfert est terminé. Les fichiers sont déplacés en waiting. Ils sont
# chargés si configuré ainsi.
sub transfer_ended {
    my $self = shift;
    my $sudoc = $self->sudoc;
    my $c = $sudoc->c;
    $self->log->notice("Réception 'status 0'. Fin transfert: 'staged' déplacé en 'waiting'\n");
    $sudoc->spool->staged_to_waiting();
    return unless $c->{loading}->{auto};

    # Chargement
    $self->log->notice("Chargement automatique des fichiers reçus\n");
    $sudoc->load_waiting();

    # Envoi des log
    my $head = Mail::Message::Head->new;
    $head->add( From    => $c->{loading}->{log}->{from} );
    $head->add( To      => $c->{loading}->{log}->{to}   );
    $head->add( Subject => 'Chargeur Sudoc Koha Tamil'  );
    my $body = Mail::Message::Body::Lines->new(
        data => path($sudoc->root . "/var/log/email.log")->slurp );
    my $message = Mail::Message->new(
        head => $head,
        body => $body );
    $message->send;
}


# Contrôle la MBOX contenant les messages envoyés par l'ABES:
# status 9: Des fichiers sont prêts à être transférés par l'ABES
# status 0: Fin transfert de fichiers
sub check_mbox {
    my $self = shift;

    # Ne rien faire si la MBOX est vide
    my $mbox = $self->sudoc->c->{trans}->{mbox};
    return unless -f $mbox;

    my $folder = $self->mgr->open( folder => $mbox, access => 'rw' );
    for my $message ($folder->messages) {
        for ($message->subject()) {
            if    ( /status is 9/ ) { $self->ask_sending($message);        }
            elsif ( /status: 0/ )   { $self->transfer_ended(); }
        }
        $message->delete;
    }
    $folder->close;
}

1;
