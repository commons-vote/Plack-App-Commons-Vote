package Plack::App::Commons::Vote;

use base qw(Plack::Component::Tags::HTML);
use strict;
use warnings;

use Commons::Vote::Action::Stats;
use Data::Commons::Vote::Competition;
use Data::FormValidator;
use Data::Printer return_value => 'dump';
use Error::Pure qw(err);
use File::Spec::Functions qw(splitdir);
use Plack::Request;
use Plack::Util::Accessor qw(backend schema);
use Tags::HTML::Form::Image::Grid;
use Tags::HTML::Login::Register;
use Tags::HTML::Commons::Vote::Competition;
use Tags::HTML::Commons::Vote::CompetitionForm;
use Tags::HTML::Commons::Vote::Competitions;
use Tags::HTML::Commons::Vote::Main;
use Tags::HTML::Commons::Vote::Menu;
use Tags::HTML::Commons::Vote::Newcomers;
use Tags::HTML::Commons::Vote::Section;
use Tags::HTML::Commons::Vote::SectionForm;
use Tags::HTML::Commons::Vote::Vote;
use Tags::HTML::Pre;
use Unicode::UTF8 qw(decode_utf8);

our $VERSION = 0.01;

sub _css {
	my $self = shift;

	$self->{'_html_menu'}->process_css;

	# Register page.
	if ($self->{'page'} eq 'register') {
		$self->{'_html_login_register'}->process_css;

	# Competition page.
	} elsif ($self->{'page'} eq 'competition') {
		$self->{'_html_competition'}->process_css;

	# Competition form page.
	} elsif ($self->{'page'} eq 'competition_form') {
		$self->{'_html_competition_form'}->process_css;

	# List of competition page.
	} elsif ($self->{'page'} eq 'competitions') {
		$self->{'_html_competitions'}->process_css;

	# Main page.
	} elsif ($self->{'page'} eq 'main') {
		$self->{'_html_main'}->process_css;

	# List of newcomers.
	} elsif ($self->{'page'} eq 'newcomers') {
		$self->{'_html_newcomers'}->process_css;

	# Section page.
	} elsif ($self->{'page'} eq 'section') {

		$self->{'_html_section'}->process_css;

	# Section form page.
	} elsif ($self->{'page'} eq 'section_form') {
		$self->{'_html_section_form'}->process_css;

	# Vote page.
	} elsif ($self->{'page'} eq 'vote') {
		$self->{'_html_vote'}->process_css;

	# XXX (debug) unknown page.
	} else {
#		$self->{'_html_pre'}->process_css;
	}

	return;
}

sub _date_from_params {
	my ($self, $date_from_params) = @_;

	my ($year, $month, $day) = split m/-/ms, $date_from_params;

	return DateTime->new(
		'day' => $day,
		'month' => $month,
		'year' => $year,
	);
}

sub _prepare_app {
	my $self = shift;

	my %p = (
		'css' => $self->css,
		'tags' => $self->tags,
	);
	$self->{'_html_form_image_grid'}
		= Tags::HTML::Form::Image::Grid->new(%p);
	$self->{'_html_login_register'} = Tags::HTML::Login::Register->new(%p);
	$self->{'_html_competition'}
		= Tags::HTML::Commons::Vote::Competition->new(%p);
	$self->{'_html_competition_form'}
		= Tags::HTML::Commons::Vote::CompetitionForm->new(
			%p,
			'form_link' => '/competition_save',
		);
	$self->{'_html_competitions'}
		= Tags::HTML::Commons::Vote::Competitions->new(%p);
	$self->{'_html_main'}
		= Tags::HTML::Commons::Vote::Main->new(%p);
	$self->{'_html_menu'}
		= Tags::HTML::Commons::Vote::Menu->new(
			%p,
			# TODO Handle logout
			'logout_url' => '/logout',
		);
	$self->{'_html_newcomers'}
		= Tags::HTML::Commons::Vote::Newcomers->new(%p);
	$self->{'_html_pre'} = Tags::HTML::Pre->new(%p);
	$self->{'_html_section'}
		= Tags::HTML::Commons::Vote::Section->new(%p);
	$self->{'_html_section_form'}
		= Tags::HTML::Commons::Vote::SectionForm->new(
			%p,
			'form_link' => '/section_save',
		);
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

	# TODO Email from auth.
	$self->{'login_email'} = 'michal.josef.spacek@wikimedia.cz';
	$self->{'login_user'} = $self->backend->fetch_person({'email' => $self->{'login_email'}});

	# Save competition.
	if ($self->{'page'} eq 'competition_save') {
		my $parameters_hr = $req->parameters->as_hashref;
		my $profile_hr = {
			'required' => ['date_from', 'date_to', 'name',],
		};
		my $results = Data::FormValidator->check($parameters_hr, $profile_hr);
		if ($results->has_invalid) {
			err "Paramters are invalid.";
		}
		my $dt_from = $self->_date_from_params($req->parameters->{'date_from'});
		my $dt_to = $self->_date_from_params($req->parameters->{'date_to'});
		my $competition = $self->backend->save_competition(
			Data::Commons::Vote::Competition->new(
				'created_by' => $self->{'user_id'},
				'dt_from' => $dt_from,
				'dt_to' => $dt_to,
				'jury_voting' => $req->parameters->{'jury_voting'} eq 'on' ? 1 : 0,
				'jury_max_marking_number' => $req->parameters->{'jury_max_marking_number'},
				'logo' => $req->parameters->{'logo'},
				'name' => $req->parameters->{'competition_name'},
				'number_of_votes' => $req->parameters->{'number_of_votes'},
				'organizer' => $req->parameters->{'organizer'},
				'organizer_logo' => $req->parameters->{'organizer_logo'},
				'public_voting' => $req->parameters->{'public_voting'} eq 'on' ? 1 : 0,
			),
		);
		my @sections = split m/\n/ms, $req->parameters->{'sections'};
		# TODO Save sections.
		if ($competition->id) {
			$self->{'page'} = 'competition';
			$self->{'page_id'} = $competition->id;

			# Redirect.
			$self->_redirect('/competition/'.$competition->id);
		} else {
			$self->{'page'} = 'competition_form';
			# TODO Values from form.
		}

	# Save sections.
	# XXX authorization?
	} elsif ($self->{'page'} eq 'section_save') {
		my $section = $self->backend->save_section({
			'created_by' => $self->{'user_id'},
			'name' => $req->parameters->{'section_name'},
			'number_of_votes' => $req->parameters->{'number_of_votes'},
		});
		if ($section->id) {
			$self->{'page'} = 'section';
			$self->{'page_id'} = $section->id;

			# Redirect.
			$self->_redirect('/section/'.$section->id);
		} else {
			$self->{'page'} = 'section_form';
			# TODO Values from form.
		}
	}

	# Main page.
	if ($self->{'page'} eq 'main') {

	# Load competition data.
	} elsif ($self->{'page'} eq 'competition') {
		if ($self->{'page_id'}) {
			$self->{'data'}->{'competition'}
				= $self->backend->fetch_competition($self->{'page_id'});
		}

	# Load competition form data.
	} elsif ($self->{'page'} eq 'competition_form') {
		if ($self->{'page_id'}) {
			$self->{'data'}->{'competition_form'}
				= $self->backend->fetch_competition($self->{'page_id'});
		}

	# Load all competition data.
	} elsif ($self->{'page'} eq 'competitions') {
		$self->{'data'}->{'competitions'}
			= [$self->backend->fetch_competitions({'created_by' => $self->{'login_user'}->id})];

	# List newcomers
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

	# Load section data.
	} elsif ($self->{'page'} eq 'section') {
		if ($self->{'page_id'}) {
			$self->{'data'}->{'section'}
				= $self->backend->fetch_section($self->{'page_id'});
		}

	# Load section form data.
	} elsif ($self->{'page'} eq 'section_form') {
		if ($self->{'page_id'}) {
			$self->{'data'}->{'section_form'}
				= $self->backend->fetch_section($self->{'page_id'});
		}

	# Vote page.
	} elsif ($self->{'page'} eq 'vote') {
		if ($self->{'page_id'}) {
			# TODO Load images in sections.
#			my @res = map {
#				{
#					'image_id' => $_->image_id,
#					'url' => decode_utf8($_->url),
#				}
#			} $self->schema->resultset('Competition')->search;
#			$self->{'data'}->{'vote'} = \@res;
		}

	# XXX Dump content
	} elsif ($self->{'page'} eq 'unknown') {
		$self->{'content'} = p $req;
	}

	return;
}

sub _tags_middle {
	my $self = shift;

	$self->{'_html_menu'}->process({
		'login_name' => $self->{'user_name'},
		'section' => $self->{'section'},
	});

	# Register page.
	if ($self->{'page'} eq 'register') {
		$self->{'_html_login_register'}->process;

	# Competition page.
	} elsif ($self->{'page'} eq 'competition') {
		$self->{'_html_competition'}->process($self->{'data'}->{'competition'});

	# Competition form page.
	} elsif ($self->{'page'} eq 'competition_form') {
		$self->{'_html_competition_form'}->process($self->{'data'}->{'competition_form'});

	# List of competitions page.
	} elsif ($self->{'page'} eq 'competitions') {
		$self->{'_html_competitions'}->process($self->{'data'}->{'competitions'});

	# Main page.
	} elsif ($self->{'page'} eq 'main') {
		$self->{'_html_main'}->process;

	# List of newcomers.
	} elsif ($self->{'page'} eq 'newcomers') {
		$self->{'_html_newcomers'}->process($self->{'data'}->{'newcomers'});

	# Section page.
	} elsif ($self->{'page'} eq 'section') {
		$self->{'_html_section'}->process($self->{'data'}->{'section'});

	# Section form page.
	} elsif ($self->{'page'} eq 'section_form') {
		$self->{'_html_section_form'}->process($self->{'data'}->{'section_form'});

	# Voting page.
	} elsif ($self->{'page'} eq 'vote') {
		$self->{'_html_vote'}->process($self->{'data'}->{'vote'});

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
