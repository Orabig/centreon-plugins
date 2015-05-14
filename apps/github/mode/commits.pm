###############################################################################
# Copyright 2005-2015 CENTREON
# Centreon is developped by : Julien Mathis and Romain Le Merlus under
# GPL Licence 2.0.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation ; either version 2 of the License.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, see <http://www.gnu.org/licenses>.
#
# Linking this program statically or dynamically with other modules is making a
# combined work based on this program. Thus, the terms and conditions of the GNU
# General Public License cover the whole combination.
#
# As a special exception, the copyright holders of this program give CENTREON
# permission to link this program with independent modules to produce an timeelapsedutable,
# regardless of the license terms of these independent modules, and to copy and
# distribute the resulting timeelapsedutable under terms of CENTREON choice, provided that
# CENTREON also meet, for each linked independent module, the terms  and conditions
# of the license of that module. An independent module is a module which is not
# derived from this program. If you modify this program, you may extend this
# exception to your version of the program, but you are not obliged to do so. If you
# do not wish to do so, delete this exception statement from your version.
#
# For more information : contact@centreon.com
# Authors : Mathieu Cinquin <mcinquin@centreon.com>
#
####################################################################################

package apps::github::mode::commits;

use base qw(centreon::plugins::mode);

use strict;
use warnings;
use centreon::plugins::httplib;
use centreon::plugins::statefile;
use JSON;
use DateTime;

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;

    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
        {
            "hostname:s"        => { name => 'hostname', default => 'api.github.com' },
            "port:s"            => { name => 'port', default => '443'},
            "proto:s"           => { name => 'proto', default => 'https' },
            "credentials"       => { name => 'credentials' },
            "username:s"        => { name => 'username' },
            "password:s"        => { name => 'password' },
            "user:s"            => { name => 'user' },
            "repository:s"      => { name => 'repository' },
            "timeout:s"         => { name => 'timeout', default => '3' },
        });

    $self->{statefile_value} = centreon::plugins::statefile->new(%options);

    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);

    if (!defined($self->{option_results}->{hostname})) {
        $self->{output}->add_option_msg(short_msg => "Please set the hostname option");
        $self->{output}->option_exit();
    }
    if ((defined($self->{option_results}->{credentials})) && (!defined($self->{option_results}->{username}) || !defined($self->{option_results}->{password}))) {
        $self->{output}->add_option_msg(short_msg => "You need to set --username= and --password= options when --credentials is used");
        $self->{output}->option_exit();
    }
    if (!defined($self->{option_results}->{repository})) {
        $self->{output}->add_option_msg(short_msg => "Please set the repository option");
        $self->{output}->option_exit();
    }
    if (!defined($self->{option_results}->{user})) {
        $self->{output}->add_option_msg(short_msg => "Please set the user option");
        $self->{output}->option_exit();
    }

    $self->{statefile_value}->check_options(%options);
}

sub run {
    my ($self, %options) = @_;

    my $repository = $self->{option_results}->{repository};
    $repository =~ tr/\//_/;
    $self->{statefile_value}->read(statefile => 'github_' . $repository . '_' . $self->{option_results}->{user} . '_' . centreon::plugins::httplib::get_port($self) . '_' . $self->{mode});
    my $old_timestamp = $self->{statefile_value}->get(name => 'last_timestamp');

    my $new_datas = {};
    $new_datas->{last_timestamp} = time();
    $self->{statefile_value}->write(data => $new_datas);

    if (!defined($old_timestamp)) {
        $self->{output}->output_add(severity => 'OK',
                                    short_msg => "Buffer creation...");
        $self->{output}->display();
        $self->{output}->exit();
    }

    # Change date format from epoch to iso8601
    my $old_iso8601 = DateTime->from_epoch(epoch => $old_timestamp)."Z";

    $self->{option_results}->{url_path} = "/repos/".$self->{option_results}->{user}."/".$self->{option_results}->{repository}."/commits";

    my $query_form_get = { per_page => '1000', since => $old_iso8601 };
    my $jsoncontent = centreon::plugins::httplib::connect($self, query_form_get => $query_form_get , connection_exit => 'critical');

    my $json = JSON->new;

    my $webcontent;

    eval {
        $webcontent = $json->decode($jsoncontent);
    };

    if ($@) {
        $self->{output}->add_option_msg(short_msg => "Cannot decode json response");
        $self->{output}->option_exit();
    }

    # Number of commits is array length
    my $nb_commits = @{$webcontent};

    $self->{output}->output_add(severity => 'OK',
                                short_msg => sprintf("Number of commits : %d", $nb_commits));
    $self->{output}->perfdata_add(label => "commits",
                                  value => $nb_commits,
                                  min => 0
                                 );

    $self->{output}->display();
    $self->{output}->exit();

}

1;

__END__

=head1 MODE

Check GitHub's number of commits for a repository

=over 8

=item B<--hostname>

IP Addr/FQDN of the GitHub's API (Default: api.github.com)

=item B<--port>

Port used by GitHub's API (Default: '443')

=item B<--proto>

Specify https if needed (Default: 'https')

=item B<--credentials>

Specify this option if you access webpage over basic authentification

=item B<--username>

Specify username

=item B<--password>

Specify password

=item B<--user>

Specify GitHub's user

=item B<--repository>

Specify GitHub's repository

=item B<--timeout>

Threshold for HTTP timeout (Default: 3)

=back

=cut