#ABSTRACT: Moo role for issuing commands, with debug support, and signal handling
package MooX::Ipc::Cmd;
use Moo::Role;
use MooX::Options;
use Config qw();
use Types::Standard qw(Object ArrayRef Str);
use Type::Params qw(compile);

# use List::Util qw(any);
use POSIX qw(WIFEXITED WEXITSTATUS WIFSIGNALED WTERMSIG);
use MooX::Log::Any;
with('MooX::Log::Any');
use feature qw(state);
use IPC::Run3;
use MooX::Ipc::Cmd::Exception;

# use namespace::clean -except=> [qw/_options_data _options_config/];

#VERSION

use constant UNDEFINED_POSIX_RE => qr{not (?:defined|a valid) POSIX macro|not implemented on this architecture};

has _cmd_signal_from_number => (
                                is            => 'lazy',
                                default       => sub {return [split(' ', $Config::Config{sig_name})]},
                                documentation => 'Posix signal number'
                               );


=attrib _cmd_kill

If set to 1 will send the propgate signal when cmd exits due to signal.

Reader: _cmd_kill

Default: 1

=cut

has _cmd_kill => (
                  is            => 'ro',
                  default       => 0,
                  documentation => 'If set to 1 will send the propogate signal when cmd exits due to signal.'
                 );

=attrib mock

Mocks the cmd, does not run

Reader: mock 

Default: 0

Command line option, via MooX::Options

=cut

option mock => (
                is            => 'ro',
                default       => 0,
                documentation => 'Mocks the cmd, does not run'
               );

=method _system(\@cmd', /%opts);

Runs a command like system call, with the output silently dropped, unless debug is on


=for :list
= Params:
 $cmd : arrayref of the command to send to the shell
= Returns:
exit code
= Exception
Throws an error when case dies, will also log error using log::any category _cmd

=cut

sub _system
{
    state $check= compile(Object, ArrayRef [Str]);
    my ($self, $cmd) = $check->(@_);
    my @ret;

    $self->logger('_cmd')->debug('Executing ' . join(' ', @$cmd));
    return 0 if ($self->mock);

    my $stderr;

    if (scalar @{$cmd} == 1)
    {
        run3($cmd->[0], \undef,
             sub {$self->_cmd_stdout($_)},
             sub {$self->_cmd_stderr($stderr, undef, $_)},
             {return_if_system_error => 1},
            );
    }
    else
    {
        run3($cmd, \undef,
             sub {$self->_cmd_stdout($_);},
             sub {$self->_cmd_stderr($stderr, undef, $_);},
             {return_if_system_error => 1},
            );
    }

    my $error = $?;
    $self->_check_error($error, $cmd, $stderr);
    return $error;
}
# =for :list
# * $cmd : arrayref of the command to send to the shell
#
# =item Returns:
#
# combined stderr stdout
#
# =item Exception
#
# Throws an error when case dies, will also log error using log::any category _cmd
#
#  
=method _capture(\@cmd',\%opts);
Runs a command like qx call.  Will display cmd executed = item Params :

=cut

sub _capture
{
    state $check= compile(Object, ArrayRef [Str]);
    my ($self, $cmd) = $check->(@_);
    $self->logger('_cmd')->debug('Executing ' . join(' ', @$cmd));

    my @ret;
    return 0 if ($self->mock);

    my $output = [];
    my $stderr;
    if (scalar @$cmd == 1)
    {
        run3($cmd->[0], \undef,
             sub {$self->_cmd_stdout($_, $output);},
             sub {$self->_cmd_stderr($stderr, $output, $_);},
             {return_if_system_error => 1});
    }
    else
    {
        run3($cmd, \undef,
             sub {$self->_cmd_stdout($_, $output);},
             sub {$self->_cmd_stderr($stderr, $output, $_);},
             {return_if_system_error => 1},
            );
    }
    my $exit_status = $?;

    $self->_check_error($exit_status, $cmd, $stderr);
    if (defined $output)
    {
        if (wantarray)
        {
            return @$output;
        }
        else
        {
            return $output;
        }
    }
    else {return}
}

sub _cmd_stdout
{
    my $self = shift;
    my ($line, $output) = @_;
    if (defined $output)
    {
        push(@$output, $line);
    }
    chomp $line;
    $self->logger('_cmd')->debug($line);
}

#sub routine to push output to the stderr and global output variables
# ignores lfs batch system concurrent spew
sub _cmd_stderr
{
    my $self   = shift;
    my $stderr = shift;
    my $output = shift;
    my $line   = $_;      # output from cmd

    return if ($line =~ / Batch system concurrent query limit exceeded/);    # ignores lfs spew
    push(@$stderr, $line);
    push(@$output, $line) if (defined $output);
    chomp $line;
    if ($self->logger('_cmd')->is_debug)
    {
        $self->logger('_cmd')->debug($line);
    }
}

#most of _check_error stolen from IPC::Simple
sub _check_error
{
    my $self = shift;
    my ($child_error, $cmd, $stderr) = @_;

    if ($child_error == -1)
    {
        my $opt = {
                   cmd         => $cmd,
                   exit_status => $child_error,
                   stderr      => $!,
                  };
        $opt->{stderr} = $stderr if (defined $stderr);
        MooX::Ipc::Cmd::Exception->throw($opt);
    }
    if (WIFSIGNALED($child_error))    # check to see if child error
    {
        my $signal_no = WTERMSIG($child_error);

        #kill with signal if told to
        if ($self->_cmd_kill)
        {
            kill $signal_no;
        }

        my $signal_name = $self->_cmd_signal_from_number->[$signal_no] || "UNKNOWN";

        my $opt = {
                   cmd         => $cmd,
                   exit_status => $child_error,
                   signal      => $signal_name,
                  };
        $opt->{stderr} = $stderr if (defined $stderr);
        MooX::Ipc::Cmd::Exception->throw($opt);
    }
    elsif ($child_error != 0)
    {
        my $opt = {
                   cmd         => $cmd,
                   exit_status => $child_error >> 8,    # get the real exit status if no signal
                  };
        $opt->{stderr} = $stderr if (defined $stderr);
        MooX::Ipc::Cmd::Exception->throw($opt);
    }
}
1;
