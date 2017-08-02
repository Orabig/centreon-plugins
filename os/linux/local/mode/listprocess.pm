#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package os::linux::local::mode::listprocess;

use base qw(centreon::plugins::mode);

use strict;
use warnings;
use centreon::plugins::misc;

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;
    
    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
                                {
                                  "hostname:s"        => { name => 'hostname' },
                                  "remote"            => { name => 'remote' },
                                  "ssh-option:s@"     => { name => 'ssh_option' },
                                  "ssh-path:s"        => { name => 'ssh_path' },
                                  "ssh-command:s"     => { name => 'ssh_command', default => 'ssh' },
                                  "timeout:s"         => { name => 'timeout', default => 30 },
                                  "sudo"              => { name => 'sudo' },
                                  "command:s"         => { name => 'command', default => 'ps' },
                                  "command-path:s"    => { name => 'command_path' },
                                  "command-options:s" => { name => 'command_options', default => 'auxh 2>&1' },
                                  "filter-process:s"  => { name => 'filter_process', },
                                  "filter-args:s"     => { name => 'filter_args', },
                                  "filter-user:s"     => { name => 'filter_user', },
                                });
    $self->{result} = {};
    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);
}

sub manage_selection {
    my ($self, %options) = @_;

    my ($stdout, $exit_code) = centreon::plugins::misc::execute(
        output => $self->{output},
        options => $self->{option_results},
        sudo => $self->{option_results}->{sudo},
        command => $self->{option_results}->{command},
        command_path => $self->{option_results}->{command_path},
        command_options => $self->{option_results}->{command_options},
        no_quit => 1
    );
    my @lines = split /\n/, $stdout;
    foreach my $line (@lines) {
        if ($line !~ /^(\S+)\s+(\d+)\s+([\d\.]+)\s+([\d\.]+)\s+\d+\s+\d+\s+\S+\s+\S+\s+\S+\s+\S+\s+(.*)/) {
			$self->{output}->output_add(long_msg => "Unknown line : $line");
			next;
		}
        my ($user,$pid,$cpu,$mem,$cmdline) = ($1, $2, $3, $4, $5);
		
		next if $pid==$$; # Do not show this process (ps aux will show however)
		
		$cmdline=~/^(\S+) ?(.*)$/ or do {
			$self->{output}->output_add(long_msg => "Cannot split cmdline : $cmdline");
			next;
			};
		my ($command,$args) = ($1,$2);
        
        if (defined($self->{option_results}->{filter_process}) && $self->{option_results}->{filter_process} ne '' &&
            $command !~ /$self->{option_results}->{filter_process}/) {
            $self->{output}->output_add(long_msg => "Skipping process '$command': no matching filter process");
            next;
        }
        if (defined($self->{option_results}->{filter_args}) && $self->{option_results}->{filter_args} ne '' &&
            $args !~ /$self->{option_results}->{filter_args}/) {
            $self->{output}->output_add(long_msg => "Skipping process '$cmdline': no matching filter args");
            next;
        }
        if (defined($self->{option_results}->{filter_user}) && $self->{option_results}->{filter_user} ne '' &&
            $user !~ /$self->{option_results}->{filter_user}/) {
            $self->{output}->output_add(long_msg => "Skipping storage '[$user] $command': no matching filter user");
            next;
        }
        
        $self->{result}->{"[$pid] $command"} = {pid => $pid, user => $user, command => $command, args => $args, cpu => $cpu, mem => $mem};
    }
}

sub run {
    my ($self, %options) = @_;
	
    $self->manage_selection();
    foreach my $pidcmd (sort(keys %{$self->{result}})) {
        $self->{output}->output_add(long_msg => "'" . $pidcmd . ' ' . $self->{result}->{$pidcmd}->{args} . 
			"' [user = " . $self->{result}->{$pidcmd}->{user} . '] [cpu = ' . $self->{result}->{$pidcmd}->{cpu} . '] [mem = ' . $self->{result}->{$pidcmd}->{mem} . ']');
    }
    
    $self->{output}->output_add(severity => 'OK',
                                short_msg => 'List process:');
    $self->{output}->display(nolabel => 1, force_ignore_perfdata => 1, force_long_output => 1);
    $self->{output}->exit();
}

sub disco_format {
    my ($self, %options) = @_;
    
    $self->{output}->add_disco_format(elements => ['user', 'command', 'args', 'cpu', 'mem', 'pid']);
}

sub disco_show {
    my ($self, %options) = @_;

    $self->manage_selection();
    foreach my $key (sort(keys %{$self->{result}})) {     
        $self->{output}->add_disco_entry(
                                         user => $self->{result}->{$key}->{user},
                                         command => $self->{result}->{$key}->{command},
                                         args => $self->{result}->{$key}->{args},
                                         cpu => $self->{result}->{$key}->{cpu},
                                         mem => $self->{result}->{$key}->{mem},
                                         pid => $self->{result}->{$key}->{pid},
                                         );
    }
}

1;

__END__

=head1 MODE

List processes.

=over 8

=item B<--remote>

Execute command remotely in 'ssh'.

=item B<--hostname>

Hostname to query (need --remote).

=item B<--ssh-option>

Specify multiple options like the user (example: --ssh-option='-l=centreon-engine' --ssh-option='-p=52').

=item B<--ssh-path>

Specify ssh command path (default: none)

=item B<--ssh-command>

Specify ssh command (default: 'ssh'). Useful to use 'plink'.

=item B<--timeout>

Timeout in seconds for the command (Default: 30).

=item B<--sudo>

Use 'sudo' to execute the command.

=item B<--command>

Command to get information (Default: 'ps').
Can be changed if you have output in a file.

=item B<--command-path>

Command path (Default: none).

=item B<--command-options>

Command options (Default: 'auxh 2>&1').

=item B<--filter-process>

Filter process (regexp can be used).

=item B<--filter-args>

Filter filesystem type (regexp can be used).

=item B<--filter-user>

Filter user (regexp can be used).

=back

=cut