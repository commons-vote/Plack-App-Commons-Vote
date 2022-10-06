package Plack::App::Commons::Vote;

use base qw(Plack::Component::Tags::HTML);
use strict;
use warnings;

use Activity::Commons::Vote::Load;
use Activity::Commons::Vote::Stats;
use Commons::Link;
use Data::Commons::Vote::Competition;
use Data::FormValidator;
use Data::Printer return_value => 'dump';
use Error::Pure qw(err);
use File::Spec::Functions qw(splitdir);
use JSON::XS;
use Plack::App::Restricted;
use Plack::Request;
use Plack::Session;
use Plack::Util::Accessor qw(backend devel schema);
use Tags::HTML::Image;
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

	# View image.
	} elsif ($self->{'page'} eq 'image') {
		$self->{'_html_image'}->process_css;

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
	}

	return;
}

sub _check_required_middleware {
	my ($self, $env) = @_;

	# Check use of Session before this app.
	if (! defined $env->{'psgix.session'}) {
		err 'No Plack::Middleware::Session present.';
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

sub _json {
	my $json = JSON::XS->new;
	$json->boolean_values(0, 1);
	return $json->utf8->allow_nonref;
}

sub _prepare_app {
	my $self = shift;

	# Wikimedia Commons link object.
	$self->{'_link'} = Commons::Link->new;

	my %p = (
		'css' => $self->css,
		'tags' => $self->tags,
	);
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
	$self->{'_html_image'} = Tags::HTML::Image->new(
		%p,
		'img_src_cb' => sub {
			my $image = shift;
			return $self->{'_link'}->link($image->commons_name);
		},
	);
	$self->{'_html_main'}
		= Tags::HTML::Commons::Vote::Main->new(%p);
	$self->{'_html_menu'}
		= Tags::HTML::Commons::Vote::Menu->new(
			%p,
			'logo_url' => '/',
			'logout_url' => '/logout',
		);
	$self->{'_html_newcomers'}
		= Tags::HTML::Commons::Vote::Newcomers->new(%p);
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

	$self->_check_required_middleware($env);

	my $req = Plack::Request->new($env);
	my $session = Plack::Session->new($env);

	# Cleanup.
	delete $self->{'data'};
	delete $self->{'page'};
	delete $self->{'page_id'};

	# Process PATH_INFO.
	if ($req->path_info =~ m/^\/(\w+)\/?(\d*)$/ms) {
		$self->{'page'} = $1;
		$self->{'page_id'} = $2 if $2;
	} else {
		$self->{'page'} = 'main';
	}

	# OAuth2
	$self->{'logged'} = 0;
	my $oauth2 = $session->get('oauth2.obj');
	my $profile_hr = {};
	if (defined $oauth2) {
		my $service_provider = $session->get('oauth2.service_provider');
		if ($service_provider eq 'Wikimedia') {
			my $res = $oauth2->get('https://meta.wikimedia.org/w/rest.php/oauth2/resource/profile');
			if ($res->is_success) {
				$profile_hr = _json()->decode($res->decoded_content);
				$self->{'login_email'} = $profile_hr->{'email'};
				$self->{'logged'} = 1;
			}
		}
	}

	# XXX Development version.
	if ($self->devel) {
		$self->{'logged'} = 1;
		$self->{'login_email'} = 'michal.josef.spacek@wikimedia.cz';
	}

	# Restricted access.
	if (! $self->{'logged'}) {
		$self->_restricted;
		return;
	}

	# Load data about person.
	$self->{'login_user'} = $self->backend->fetch_person({'email' => $self->{'login_email'}});
	if (! defined $self->{'login_user'}) {
		$self->{'login_user'} = $self->backend->save_person(Data::Commons::Vote::Person->new(
			'email' => $self->{'login_email'},
			'wm_username' => $profile_hr->{'username'},
			$profile_hr->{'realname'} ? (
				'name' => $profile_hr->{'realname'},
			) : (),
		));
	}

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
		my $jury_voting = defined $req->parameters->{'jury_voting'}
			&& $req->parameters->{'jury_voting'} eq 'on' ? 1 : 0;
		my ($dt_jury_voting_from, $dt_jury_voting_to);
		if ($jury_voting) {
			$dt_jury_voting_from = $self->_date_from_params(
				$req->parameters->{'jury_voting_date_from'});
			$dt_jury_voting_to = $self->_date_from_params(
				$req->parameters->{'jury_voting_date_from'});
		}
		my $public_voting = defined $req->parameters->{'public_voting'}
			&& $req->parameters->{'public_voting'} eq 'on' ? 1 : 0;
		my ($dt_public_voting_from, $dt_public_voting_to);
		if ($public_voting) {
			$dt_public_voting_from = $self->_date_from_params(
				$req->parameters->{'public_voting_date_from'});
			$dt_public_voting_to = $self->_date_from_params(
				$req->parameters->{'public_voting_date_from'});
		}
		my $competition_id = $req->parameters->{'competition_id'} || undef;
		my $competition_to_update = Data::Commons::Vote::Competition->new(
			'created_by' => $self->{'login_user'},
			'dt_from' => $dt_from,
			'dt_jury_voting_from' => $dt_jury_voting_from,
			'dt_jury_voting_to' => $dt_jury_voting_to,
			'dt_public_voting_from' => $dt_public_voting_from,
			'dt_public_voting_to' => $dt_public_voting_to,
			'dt_to' => $dt_to,
			'id' => $competition_id,
			'jury_voting' => $jury_voting,
			'jury_max_marking_number' => $req->parameters->{'jury_max_marking_number'} || undef,
			'logo' => decode_utf8($req->parameters->{'logo'}) || undef,
			'name' => decode_utf8($req->parameters->{'competition_name'}),
			'number_of_votes' => $req->parameters->{'number_of_votes'} || undef,
			'organizer' => decode_utf8($req->parameters->{'organizer'}) || undef,
			'organizer_logo' => decode_utf8($req->parameters->{'organizer_logo'}) || undef,
			'public_voting' => $public_voting,
		);
		my $competition;
		if ($competition_id) {
			$competition = $self->backend->update_competition(
				$competition_to_update,
			);
		} else {
			$competition = $self->backend->save_competition(
				$competition_to_update,
			);
		}
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
	} elsif ($self->{'page'} eq 'section_save') {
		my $parameters_hr = $req->parameters->as_hashref;
		my $profile_hr = {
			'required' => ['competition_id', 'section_name',],
		};
		my $results = Data::FormValidator->check($parameters_hr, $profile_hr);
		if ($results->has_invalid) {
			err "Paramters are invalid.";
		}
		my $competition = $self->backend->fetch_competition($req->parameters->{'competition_id'});
		if (! $competition) {
			err "Bad competition.";
		}
		my $section_id = $req->parameters->{'section_id'};
		my $section_to_update = Data::Commons::Vote::Section->new(
			'competition' => $competition,
			'created_by' => $self->{'login_user'},
			'id' => $section_id || undef,
			'logo' => decode_utf8($req->parameters->{'logo'}) || undef,
			'name' => decode_utf8($req->parameters->{'section_name'}),
			'number_of_votes' => $req->parameters->{'number_of_votes'} || undef,
		);
		my $section;
		if ($section_id) {
			$section = $self->backend->update_section(
				$section_to_update,
			);
		} else {
			$section = $self->backend->save_section(
				$section_to_update,
			);
		}
		if (defined $req->parameters->{'categories'}) {
			foreach my $category_name (split m/\r\n/ms, $req->parameters->{'categories'}) {
				my $category = Data::Commons::Vote::Category->new(
					'created_by' => $self->{'login_user'},
					'category' => decode_utf8($category_name),
					'section_id' => $section->id,
				);
				$self->backend->save_section_category($category);
			}
		}
		if ($section->id) {
			$self->{'page'} = 'section';
			$self->{'page_id'} = $section->id;

			# Redirect.
			$self->_redirect('/section/'.$section->id);
		} else {
			$self->{'page'} = 'section_form';
			# TODO Values from form.
		}

	# Remove section.
	} elsif ($self->{'page'} eq 'section_remove') {
		if ($self->{'page_id'}) {
			my $section = $self->backend->delete_section($self->{'page_id'});

			# Redirect.
			$self->_redirect('/competition/'.$section->competition->id);
		}

	}

	# Main page.
	if ($self->{'page'} eq 'main') {
		# XXX
		$self->{'section'} = $self->{'_html_main'}->{'text'}->{'eng'}->{'my_competitions'};
		$self->{'data'}->{'competitions'}
			= [$self->backend->fetch_competitions({'created_by_id' => $self->{'login_user'}->id})];

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
			= [$self->backend->fetch_competitions({'created_by_id' => $self->{'login_user'}->id})];

	# View image.
	} elsif ($self->{'page'} eq 'image') {

		# Image id.
		if ($self->{'page_id'}) {
			$self->{'data'}->{'image'} = $self->backend->fetch_image($self->{'page_id'});
		}

	# Load competition from Wikimedia Commons.
	} elsif ($self->{'page'} eq 'load') {
		if ($self->{'page_id'}) {
			my $load = Activity::Commons::Vote::Load->new(
				'backend' => $self->backend,
				'creator' => $self->{'login_user'},
			);
			# XXX recursive opts?
			$load->load($self->{'page_id'});

			# Redirect.
			$self->_redirect('/competition/'.$self->{'page_id'});
		}

	# List newcomers
	} elsif ($self->{'page'} eq 'newcomers') {
		if ($self->{'page_id'}) {
			my $stats = Activity::Commons::Vote::Stats->new(
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
		} else {
			my $competition_id = $req->parameters->{'competition_id'};
			if ($competition_id) {
				$self->{'data'}->{'competition'}
					= $self->backend->fetch_competition($competition_id);
			} else {
				err "No competition id.";
			}
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
		'login_name' => $self->{'login_user'}->name || $self->{'login_user'}->wm_username,
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

	# View image.
	} elsif ($self->{'page'} eq 'image') {
		$self->{'_html_image'}->process($self->{'data'}->{'image'});

	# Main page.
	} elsif ($self->{'page'} eq 'main') {
		$self->{'_html_main'}->process($self->{'data'}->{'competitions'});

	# List of newcomers.
	} elsif ($self->{'page'} eq 'newcomers') {
		$self->{'_html_newcomers'}->process($self->{'data'}->{'newcomers'});

	# Section page.
	} elsif ($self->{'page'} eq 'section') {
		$self->{'_html_section'}->process($self->{'data'}->{'section'});

	# Section form page.
	} elsif ($self->{'page'} eq 'section_form') {
		$self->{'_html_section_form'}->process(
			$self->{'data'}->{'section_form'},
			$self->{'data'}->{'competition'},
		);

	# Voting page.
	} elsif ($self->{'page'} eq 'vote') {
		$self->{'_html_vote'}->process($self->{'data'}->{'vote'});

	# XXX (debug) Unknown.
	} else {
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

sub _restricted {
	my $self = shift;

	$self->psgi_app(
		Plack::App::Restricted->new(
			'css' => $self->css,
			'tags' => $self->tags,
		)->to_app->(),
	);

	return;
}

1;

__END__
