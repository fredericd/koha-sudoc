package EchoWatcher;
use Moose;
use POE;

has delay   => ( is => 'rw', isa => 'Int', default => 1 );
has action  => ( is => 'rw', does => 'WatchableTask' );
has stopped => ( is => 'rw', isa => 'Int', default => 0 );


sub start {
    my $self = shift;
    POE::Session->create(
        inline_states => {
            _start => sub { 
                $self->action()->start_message();
                $_[HEAP]{watcher_alarm_id} 
                    = $_[KERNEL]->alarm_set( tick => time() + $self->delay(), $self->action() );
            },
            tick => sub {
                my $echo = $_[ARG0];
                $echo->process_message();
                $_[HEAP]{watcher_alarm_id} 
                 = $_[KERNEL]->alarm_set( tick => time()+$self->delay(), $echo );
            },
       },
    );
}


sub stop {
    my $self = shift;
    $self->action()->end_message();

    #FIXME: It should be better to stop only the watcher and not all processes
    POE::Kernel->stop();
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

