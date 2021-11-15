package Plack::App::Commons::Vote;

use base qw(Plack::Component::Tags::HTML);
use strict;
use warnings;

use Commons::Vote::Action::Stats;
use Commons::Vote::Backend;
use Data::Printer return_value => 'dump';
use File::Spec::Functions qw(splitdir);
use Plack::Request;
use Plack::Util::Accessor qw(schema);
use Tags::HTML::Login::Access;
use Tags::HTML::Login::Register;
use Tags::HTML::Commons::Vote::Competition;
use Tags::HTML::Commons::Vote::CompetitionForm;
use Tags::HTML::Commons::Vote::Competitions;
use Tags::HTML::Commons::Vote::Main;
use Tags::HTML::Commons::Vote::Newcomers;
use Tags::HTML::Commons::Vote::Vote;
use Tags::HTML::Pre;
use Unicode::UTF8 qw(decode_utf8);

our $VERSION = 0.01;

sub _css {
	my $self = shift;

	# Register page.
	if ($self->{'page'} eq 'register') {
		$self->{'_html_login_register'}->process_css;

	# Competition page.
	} elsif ($self->{'page'} eq 'competition'
		&& $self->{'authorize'}) {

		$self->{'_html_competition'}->process_css;

	# Competition form page.
	} elsif ($self->{'page'} eq 'competition_form'
		&& $self->{'authorize'}) {

		$self->{'_html_competition_form'}->process_css;

	# List of competition page.
	} elsif ($self->{'page'} eq 'competitions'
		&& $self->{'authorize'}) {

		$self->{'_html_competitions'}->process_css;

	# Main page.
	} elsif ($self->{'page'} eq 'main'
		&& $self->{'authorize'}) {

		$self->{'_html_main'}->process_css;

	# List of newcomers.
	} elsif ($self->{'page'} eq 'newcomers'
		&& $self->{'authorize'}) {
		$self->{'_html_newcomers'}->process_css;
	# Login page.
	} elsif ($self->{'page'} eq 'login'
		|| ! $self->{'authorize'}) {

		$self->{'_html_login_access'}->process_css;

	# XXX (debug) unknown page.
	} else {
#		$self->{'_html_pre'}->process_css;
	}

	return;
}

sub _prepare_app {
	my $self = shift;

	$self->{'_backend'} = Commons::Vote::Backend->new(
		'schema' => $self->schema,
	);

	my %p = (
		'css' => $self->css,
		'tags' => $self->tags,
	);
	$self->{'_html_login_access'} = Tags::HTML::Login::Access->new(%p);
	$self->{'_html_login_register'} = Tags::HTML::Login::Register->new(%p);
	$self->{'_html_competitions'} = Tags::HTML::Commons::Vote::Competitions->new(%p);
	$self->{'_html_competition'}
		= Tags::HTML::Commons::Vote::Competition->new(%p);
	$self->{'_html_competition_form'}
		= Tags::HTML::Commons::Vote::CompetitionForm->new(
			%p,
			'form_link' => '/competition_save',
		);
	$self->{'_html_main'}
		= Tags::HTML::Commons::Vote::Main->new(%p);
	$self->{'_html_newcomers'}
		= Tags::HTML::Commons::Vote::Newcomers->new(%p);
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
		$self->{'page'} = 'main';
	}

	$self->{'authorize'} = 1;
	$self->{'user_id'} = 1;
	if (! $self->{'authorize'}) {
		my $user = $req->parameters->{'username'};
		my $pass = $req->parameters->{'password'};
		if (! defined $user || $user ne 'foo' || ! defined $pass || $pass ne 'bar') {
			return;
		} else {
			$self->{'authorize'} = 1;
		}
	}

	# Save competition.
	# XXX authorization?
	if ($self->{'page'} eq 'competition_save') {
		my $competition = $self->{'_backend'}->save_competition({
			'created_by' => $self->{'user_id'},
			'date_from' => $req->parameters->{'date_from'},
			'date_to' => $req->parameters->{'date_to'},
			'logo' => $req->parameters->{'logo'},
			'name' => $req->parameters->{'competition_name'},
			'number_of_votes' => $req->parameters->{'number_of_votes'},
			'organizer' => $req->parameters->{'organizer'},
			'organizer_logo' => $req->parameters->{'organizer_logo'},
		});
		my @sections = split m/\n/ms, $req->parameters->{'sections'};
		if ($competition->id) {
			$self->{'page'} = 'competition';
			$self->{'page_id'} = $competition->id;

			# Redirect.
			$self->_redirect('/competition/'.$competition->id);
		} else {
			$self->{'page'} = 'competition_form';
			# TODO Values from form.
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
	# Main page.
	if ($self->{'page'} eq 'main') {

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
	# Load competition form data.
	} elsif ($self->{'page'} eq 'competition_form') {
		if ($self->{'page_id'}) {
			$self->{'data'}->{'competition_form'}
				= $self->{'_backend'}->fetch_competition($self->{'page_id'});
		}

	} elsif ($self->{'page'} eq 'newcomers') {
		if ($self->{'page_id'}) {
			my $stats = Commons::Vote::Action::Stats->new(
				'schema' => $self->schema,
			);
			$self->{'data'}->{'newcomers'}
				= [$stats->newcomers($self->{'page_id'})];
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

	# Register page.
	if ($self->{'page'} eq 'register') {
		$self->{'_html_login_register'}->process;

	# Competition page.
	} elsif ($self->{'page'} eq 'competition'
		&& $self->{'authorize'}) {

		$self->{'_html_competition'}->process($self->{'data'}->{'competition'});

	# Competition form page.
	} elsif ($self->{'page'} eq 'competition_form'
		&& $self->{'authorize'}) {

		$self->{'_html_competition_form'}->process($self->{'data'}->{'competition_form'});

	# List of competitions page.
	} elsif ($self->{'page'} eq 'competitions'
		&& $self->{'authorize'}) {

		$self->{'_html_competitions'}->process($self->{'data'}->{'competitions'});

	# Main page.
	} elsif ($self->{'page'} eq 'main'
		&& $self->{'authorize'}) {

		$self->{'_html_main'}->process;

	# List of newcomers.
	} elsif ($self->{'page'} eq 'newcomers'
		&& $self->{'authorize'}) {

		$self->{'_html_newcomers'}->process($self->{'data'}->{'newcomers'});

	# Login page.
	} elsif ($self->{'page'} eq 'login'
		|| ! $self->{'authorize'}) {

		$self->{'_html_login_access'}->process;

	# XXX (debug) Unknown.
	} else {
		$self->{'_html_pre'}->process($self->{'content'});
	}

	return;
}

sub _redirect {
	my ($self, $location) = @_;

	$self->psgi_app([
		'303',
		[
			'Location' => $location,
			'Content-Type' => 'text/plain',
		],
		['Saved and Moved'],
	]);

	return;
}

1;

__END__
