package Plack::App::Commons::Vote;

use base qw(Plack::Component::Tags::HTML);
use strict;
use warnings;

use Data::Printer return_value => 'dump';
use File::Spec::Functions qw(splitdir);
use Plack::Request;
use Plack::Util::Accessor qw(schema);
use Tags::HTML::Login::Access;
use Tags::HTML::Login::Register;
use Tags::HTML::Commons::Vote::Competition;
use Tags::HTML::Commons::Vote::Competitions;
use Tags::HTML::Commons::Vote::Vote;
use Tags::HTML::Pre;
use Unicode::UTF8 qw(decode_utf8);

our $VERSION = 0.01;

sub _css {
	my $self = shift;

	if ($self->{'page'} eq 'register') {
		$self->{'_html_login_register'}->process_css;
	} elsif ($self->{'page'} eq 'competition'
		&& $self->{'authorize'}) {

		$self->{'_html_competition'}->process_css;
	} elsif ($self->{'page'} eq 'competitions'
		&& $self->{'authorize'}) {

		$self->{'_html_competitions'}->process_css;
	} elsif ($self->{'page'} eq 'login'
		|| ! $self->{'authorize'}) {

		$self->{'_html_login_access'}->process_css;
	} else {
#		$self->{'_html_pre'}->process_css;
	}

	return;
}

sub _prepare_app {
	my $self = shift;

	my %p = (
		'css' => $self->css,
		'tags' => $self->tags,
	);
	$self->{'_html_login_access'} = Tags::HTML::Login::Access->new(%p);
	$self->{'_html_login_register'} = Tags::HTML::Login::Register->new(%p);
	$self->{'_html_competition'} = Tags::HTML::Commons::Vote::Competition->new(%p);
	$self->{'_html_competitions'} = Tags::HTML::Commons::Vote::Competitions->new(%p);
	$self->{'_html_pre'} = Tags::HTML::Pre->new(%p);
	$self->{'_html_vote'} = Tags::HTML::Commons::Vote::Vote->new(%p);

	return;
}

sub _process_actions {
	my ($self, $env) = @_;

	my $req = Plack::Request->new($env);

	# Process PATH_INFO.
	if ($req->path_info =~ m/^\/(\w+)\/?(\d*)$/ms) {
		$self->{'page'} = $1;
		$self->{'page_id'} = $2 if $2;
	} else {
		$self->{'page'} = 'unknown';
	}

	$self->{'authorize'} = 1;
	if (! $self->{'authorize'}) {
		my $user = $req->parameters->{'username'};
		my $pass = $req->parameters->{'password'};
		if (! defined $user || $user ne 'foo' || ! defined $pass || $pass ne 'bar') {
			return;
		} else {
			$self->{'authorize'} = 1;
		}
	}


	# Load all competition data.
	if ($self->{'page'} eq 'competitions') {
		my @res = map {
			{
				'competition_id' => $_->competition_id,
				'date_from' => $_->date_from,
				'date_to' => $_->date_to,
				'name' => decode_utf8($_->name),
			}
		} $self->schema->resultset('Competition')->search;
		$self->{'data'}->{'competitions'} = \@res;

	# Load competition data.
	} elsif ($self->{'page'} eq 'competition') {
		if ($self->{'page_id'}) {
			my $res = $self->schema->resultset('Competition')->search(undef,
				{ competition_id => $self->{'page_id'} })->single;
			$self->{'data'}->{'competition'} = {
				'date_from' => $res->date_from,
				'date_to' => $res->date_to,
				'logo' => decode_utf8($res->logo),
				'name' => decode_utf8($res->name),
				'organizer' => decode_utf8($res->organizer),
				'organizer_logo' => decode_utf8($res->organizer_logo),
			};
		}

	# Register page.
	} elsif ($self->{'page'} eq 'register') {

	# XXX Dump content
	} elsif ($self->{'page'} eq 'unknown') {
		$self->{'content'} = p $req;
	}

	return;
}

sub _tags_middle {
	my $self = shift;

	if ($self->{'page'} eq 'register') {
		$self->{'_html_login_register'}->process;
	} elsif ($self->{'page'} eq 'competition'
		&& $self->{'authorize'}) {

		$self->{'_html_competition'}->process($self->{'data'}->{'competition'});
	} elsif ($self->{'page'} eq 'competitions'
		&& $self->{'authorize'}) {

		$self->{'_html_competitions'}->process($self->{'data'}->{'competitions'});
	} elsif ($self->{'page'} eq 'login'
		|| ! $self->{'authorize'}) {

		$self->{'_html_login_access'}->process;
	} else {
		$self->{'_html_pre'}->process($self->{'content'});
	}

	return;
}

1;

__END__
