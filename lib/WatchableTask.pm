package WatchableTask;
use Moose::Role;

requires 'run';
requires 'process';
requires 'process_message';
requires 'start_message';
requires 'end_message';

1;

=head1 COPYRIGHT AND LICENSE

Copyright 2011 by Tamil, s.a.r.l.

L<http://www.tamil.fr>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
