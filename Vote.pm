package Plack::App::Commons::Vote;

use base qw(Plack::Component::Tags::HTML);
use strict;
use warnings;

use Activity::Commons::Vote::Delete;
use Activity::Commons::Vote::Load;
use Activity::Commons::Vote::Stats;
use Activity::Commons::Vote::Validation;
use Commons::Link;
use Commons::Vote::Fetcher;
use Data::Commons::Vote::Competition;
use Data::Commons::Vote::CompetitionValidation;
use Data::Commons::Vote::CompetitionValidationOption;
use Data::Commons::Vote::Log;
use Data::Commons::Vote::Theme;
use Data::Commons::Vote::ThemeImage;
use Data::FormValidator;
use Data::HTML::A;
use Data::Printer return_value => 'dump';
use Error::Pure qw(err);
use File::Spec::Functions qw(splitdir);
use JSON::XS;
use Plack::App::Restricted;
use Plack::Request;
use Plack::Session;
use Plack::Util::Accessor qw(backend devel schema);
use Readonly;
use Tags::HTML::Commons::Vote::Competition;
use Tags::HTML::Commons::Vote::CompetitionForm;
use Tags::HTML::Commons::Vote::CompetitionValidation;
use Tags::HTML::Commons::Vote::CompetitionValidationForm;
use Tags::HTML::Commons::Vote::Competitions;
use Tags::HTML::Commons::Vote::Main;
use Tags::HTML::Commons::Vote::Menu;
use Tags::HTML::Commons::Vote::Newcomers;
use Tags::HTML::Commons::Vote::Section;
use Tags::HTML::Commons::Vote::SectionForm;
use Tags::HTML::Commons::Vote::ThemeForm;
use Tags::HTML::Commons::Vote::Vote;
use Tags::HTML::Image;
use Tags::HTML::Image::Grid;
use Tags::HTML::Login::Register;
use Tags::HTML::Pager;
use Tags::HTML::Pager::Utils qw(adjust_actual_page compute_index_values pages_num);
use Tags::HTML::Pre;
use Tags::HTML::Table::View;
use Unicode::UTF8 qw(decode_utf8 encode_utf8);

Readonly::Scalar our $IMAGE_GRID_WIDTH => 340;
Readonly::Scalar our $IMAGES_ON_PAGE => 24;

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

	# View images.
	} elsif ($self->{'page'} eq 'images') {
		$self->{'_html_pager'}->process_css;
		$self->{'_html_images'}->process_css;

	# Log record.
	} elsif ($self->{'page'} eq 'log') {
		$self->{'_html_pre'}->process_css;

	# Log list.
	} elsif ($self->{'page'} eq 'logs') {
		$self->{'_html_table_view'}->process_css;

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

	# Validation page.
	} elsif ($self->{'page'} eq 'validation') {
		$self->{'_html_competition_validation'}->process_css;

	# Validation form page.
	} elsif ($self->{'page'} eq 'validation_form') {
		$self->{'_html_competition_validation_form'}->process_css;

	# Theme form page.
	} elsif ($self->{'page'} eq 'theme_form') {
		$self->{'_html_theme_form'}->process_css;

	# Vote page.
	} elsif ($self->{'page'} eq 'vote') {
		$self->{'_html_vote'}->process_css;
	}

	return;
}

sub _check_access {
	my ($self, $cond_hr) = @_;

	if (exists $cond_hr->{'competition_id'}) {
		my $count = $self->backend->count_competition({
			'competition_id' => $cond_hr->{'competition_id'},
			'created_by_id' => $self->{'login_user'}->id,
		});
		if ($count) {
			return 1;
		}
	}

	return 0;
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

	# Commons fetcher.
	$self->{'_fetcher'} = Commons::Vote::Fetcher->new;

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
	$self->{'_html_competition_validation'}
		= Tags::HTML::Commons::Vote::CompetitionValidation->new(%p);
	$self->{'_html_competition_validation_form'}
		= Tags::HTML::Commons::Vote::CompetitionValidationForm->new(
			%p,
			'form_link' => '/validation_save',
		);
	$self->{'_html_competitions'}
		= Tags::HTML::Commons::Vote::Competitions->new(%p);
	$self->{'_html_image'} = Tags::HTML::Image->new(
		%p,
		'fit_minus' => '110px',
		'img_src_cb' => sub {
			my $image = shift;
			return $self->{'_link'}->thumb_link($image->commons_name, 1630);
		},
	);
	$self->{'_html_images'} = Tags::HTML::Image::Grid->new(
		%p,
		'img_link_cb' => sub {
			my $image = shift;
			return '/image/'.$image->id;
		},
		'img_src_cb' => sub {
			my $image = shift;
			return $self->{'_link'}->thumb_link($image->commons_name, $IMAGE_GRID_WIDTH);
		},
		'img_width' => $IMAGE_GRID_WIDTH,
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
	$self->{'_html_pager'} = Tags::HTML::Pager->new(
		%p,
		'url_page_cb' => sub {
			my $page = shift;

			return '?page_num='.$page;
		},
	);
	$self->{'_html_pre'} = Tags::HTML::Pre->new(
		%p,
	);
	$self->{'_html_section'}
		= Tags::HTML::Commons::Vote::Section->new(%p);
	$self->{'_html_section_form'}
		= Tags::HTML::Commons::Vote::SectionForm->new(
			%p,
			'form_link' => '/section_save',
		);
	$self->{'_html_table_view'} = Tags::HTML::Table::View->new(%p,
		'header' => 1,
	);
	$self->{'_html_theme_form'}
		= Tags::HTML::Commons::Vote::ThemeForm->new(
			%p,
			'form_link' => '/theme_save',
		);
	$self->{'_html_vote'} = Tags::HTML::Commons::Vote::Vote->new(%p,
		'form_link' => '/vote_save',
	);

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
	$self->script_js([]);
	$self->script_js_src([]);

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
		$self->{'login_user'} = $self->backend->fetch_person({'wm_username' => $profile_hr->{'username'}});
		my $dt_first_upload = $self->{'_fetcher'}->date_of_first_upload($profile_hr->{'username'});
		my $person_to_update_or_create = Data::Commons::Vote::Person->new(
			'email' => $self->{'login_email'},
			'first_upload_at' => $dt_first_upload,
			$profile_hr->{'realname'} ? (
				'name' => $profile_hr->{'realname'},
			) : (),
			'wm_username' => $profile_hr->{'username'},
		);
		if (! defined $self->{'login_user'}) {
			$self->{'login_user'} = $self->backend->save_person($person_to_update_or_create);
		} else {
			$self->{'login_user'} = $self->backend->update_person($self->{'login_user'}->id,
				$person_to_update_or_create);
		}
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
			'wd_qid' => $req->parameters->{'wd_qid'} || undef,
		);
		my $competition;
		if ($competition_id) {
			$competition = $self->backend->fetch_competition($competition_id);
			if ($competition->created_by->id eq $self->{'login_user'}->id) {
				$competition = $self->backend->update_competition(
					$competition_to_update,
				);
				my $log_type = $self->backend->fetch_log_type_name('update_competition');
				my $log = 'Competition updated.';
				$self->backend->save_log(
					Data::Commons::Vote::Log->new(
						'competition' => $competition,
						'created_by' => $self->{'login_user'},
						'log' => $log,
						'log_type' => $log_type,
					),
				);
			} else {
				err 'Cannot update competition.';
			}
		} else {
			$competition = $self->backend->save_competition(
				$competition_to_update,
			);
			my $log_type = $self->backend->fetch_log_type_name('create_competition');
			$self->backend->save_log(
				Data::Commons::Vote::Log->new(
					'competition' => $competition,
					'created_by' => $self->{'login_user'},
					# TODO Information which was uploaded.
					'log' => 'Competition created.',
					'log_type' => $log_type,
				),
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

	# Save section.
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

		# Remove loaded_at from competition
		$self->backend->schema->resultset('Competition')->update({
			'images_loaded_at' => undef,
		});
		foreach my $section (@{$competition->sections}) {
			$self->backend->delete_section_images($section->id);
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

			# Remove dt_image_loaded from competition.
			my $old_competition_id = $section->competition->id;
			my $count_sections = $self->backend->count_competition_sections($old_competition_id);
			if ($count_sections == 0) {
				$self->backend->schema->resultset('Competition')->update({
					'images_loaded_at' => undef,
				});
			}

			# Redirect.
			$self->_redirect('/competition/'.$section->competition->id);
		}

	# Save theme.
	} elsif ($self->{'page'} eq 'theme_save') {
		my $parameters_hr = $req->parameters->as_hashref;
		my $profile_hr = {
			'required' => ['theme_name',],
		};
		my $results = Data::FormValidator->check($parameters_hr, $profile_hr);
		if ($results->has_invalid) {
			err "Paramters are invalid.";
		}
		my $theme_id = $req->parameters->{'theme_id'};
		my $theme_to_update = Data::Commons::Vote::Theme->new(
			'created_by' => $self->{'login_user'},
			'id' => $theme_id || undef,
			'name' => decode_utf8($req->parameters->{'theme_name'}),
			'shortcut' => decode_utf8($req->parameters->{'theme_shortcut'}) || undef,
		);
		my $theme;
		if ($theme_id) {
			$theme = $self->backend->update_theme(
				$theme_to_update,
			);
		} else {
			$theme = $self->backend->save_theme(
				$theme_to_update,
			);
		}
		if (defined $req->parameters->{'images'}) {
			foreach my $image_on_commons (split m/\r\n/ms, $req->parameters->{'images'}) {
				my $load = Activity::Commons::Vote::Load->new(
					'backend' => $self->backend,
					'creator' => $self->{'login_user'},
					'verbose_cb' => sub {
						my $message = shift;
						$env->{'psgi.errors'}->print(encode_utf8($message)."\n");
					},
				);
				my $image = $load->load_commons_image(decode_utf8($image_on_commons));
				my $theme_image = Data::Commons::Vote::ThemeImage->new(
					'created_by' => $self->{'login_user'},
					'theme_id' => $theme->id,
					'image' => $image,
				);
				$self->backend->save_theme_image($theme_image);
			}
		}
		if ($theme->id) {
			$self->{'page'} = 'theme';
			$self->{'page_id'} = $theme->id;

			# Redirect.
			$self->_redirect('/theme/'.$theme->id);
		} else {
			$self->{'page'} = 'theme_form';
			# TODO Values from form.
		}

	# Remove validation.
	} elsif ($self->{'page'} eq 'validation_remove') {
		if ($self->{'page_id'}) {
			$self->backend->delete_competition_validation_options($self->{'page_id'});
			my $validation = $self->backend->delete_competition_validation($self->{'page_id'});

			# Redirect.
			$self->_redirect('/competition/'.$validation->competition->id);
		}

	# Save validation.
	} elsif ($self->{'page'} eq 'validation_save') {
		my $parameters_hr = $req->parameters->as_hashref;
		my $profile_hr = {
			'required' => ['competition_id', 'validation_type_id'],
		};
		my $results = Data::FormValidator->check($parameters_hr, $profile_hr);
		if ($results->has_invalid) {
			err "Paramters are invalid.";
		}

		my $competition_id = $req->parameters->{'competition_id'};
		my $competition = $self->backend->fetch_competition($competition_id);

		my $validation_type_id = $req->parameters->{'validation_type_id'};
		my $validation_type = $self->backend->fetch_validation_type({
			'validation_type_id' => $validation_type_id,
		});

		my $competition_validation = Data::Commons::Vote::CompetitionValidation->new(
			'competition' => $competition,
			'created_by' => $self->{'login_user'},
			'validation_type' => $validation_type,
		);
		$competition_validation = $self->backend->save_competition_validation($competition_validation);

		# Fetch validation options.
		my @validation_type_options = $self->backend->fetch_validation_type_options($validation_type_id);
		foreach my $validation_type_option (@validation_type_options) {
			my $value = $req->parameters->{$validation_type_option->option};
			if (! defined $value) {
				err "Parameter '".$validation_type_option->option."' is required.";
			}
			my $competition_validation_option = Data::Commons::Vote::CompetitionValidationOption->new(
				'competition_validation' => $competition_validation,
				'created_by' => $self->{'login_user'},
				'validation_option' => $validation_type_option,
				'value' => $value,
			);
			$competition_validation_option = $self->backend->save_competition_validation_option($competition_validation_option);
		}

		if ($competition_validation->id) {
			$self->{'page'} = 'competition';
			$self->{'page_id'} = $competition_validation->competition->id;

			# Redirect.
			$self->_redirect('/competition/'.$competition_validation->competition->id);
		} else {
			$self->{'page'} = 'validation_form';
		}

	# Save vote.
	} elsif ($self->{'page'} eq 'vote_save') {
		my $competition_id = $req->parameters->{'competition_id'};
		my $image_id = $req->parameters->{'image_id'};
		my $vote_type_id = $req->parameters->{'vote_type_id'};
		# TODO vote

		# Check type of voting.
		# TODO

		# Check date of voting.
		# TODO

		my $competition = $self->backend->fetch_competition({
			'competition_id' => $competition_id,
		});
		my $image = $self->backend->fetch_image({
			'image_id' => $image_id,
		});
		my $vote_type = $self->backend->fetch_vote_type({
			'vote_type_id' => $vote_type_id,
		});

		my $vote = $self->backend->save_vote(Data::Commons::Vote::Vote->new(
			'competition' => $competition,
			'image' => $image,
			'person' => $self->{'login_user'},
			'vote_type' => $vote_type,
			'vote_value' => 1,
		));
	}

	# Main page.
	if ($self->{'page'} eq 'main') {
		# XXX
		$self->{'section'} = $self->{'_html_main'}->{'text'}->{'eng'}->{'my_competitions'};
		$self->{'data'}->{'competitions'}
			= [$self->backend->fetch_competitions({'created_by_id' => $self->{'login_user'}->id})];

	# Load competition data.
	} elsif ($self->{'page'} eq 'competition') {
		if ($self->{'page_id'} && $self->_check_access({'competition_id' => $self->{'page_id'}})) {
			$self->{'data'}->{'competition'}
				= $self->backend->fetch_competition($self->{'page_id'});
		}

	# Load competition form data.
	} elsif ($self->{'page'} eq 'competition_form') {
		if ($self->{'page_id'} && $self->_check_access({'competition_id' => $self->{'page_id'}})) {
			$self->{'data'}->{'competition_form'}
				= $self->backend->fetch_competition($self->{'page_id'});
		}
		$self->{'_html_competition_form'}->init(
			$self->{'data'}->{'competition_form'},
		);

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

	# View images.
	} elsif ($self->{'page'} eq 'images') {

		# Section id.
		if ($self->{'page_id'}) {

			# Get information about section.
			$self->{'data'}->{'section'} = $self->backend->fetch_section($self->{'page_id'});

			# URL parameters.
			my $page_num = $req->parameters->{'page_num'} || 1;

			# Count images.
			$self->{'data'}->{'images_count'}
				= $self->backend->count_section_images($self->{'page_id'});
			my $pages = pages_num($self->{'data'}->{'images_count'}, $IMAGES_ON_PAGE);
			my $actual_page = adjust_actual_page($page_num, $pages);
			my ($begin_index) = compute_index_values($self->{'data'}->{'images_count'},
				$actual_page, $IMAGES_ON_PAGE);

			# Fetch selected images.
			$self->{'data'}->{'images'} = [$self->backend->fetch_section_images($self->{'page_id'}, {
				'offset' => $begin_index,
				'rows' => $IMAGES_ON_PAGE,
			})];

			# Pager.
			$self->{'data'}->{'pager'} = {
				'actual_page' => $actual_page,
				'pages_num' => $pages,
			};
		}

	# Load competition from Wikimedia Commons.
	} elsif ($self->{'page'} eq 'load') {
		if ($self->{'page_id'}) {
			my %p = (
				'backend' => $self->backend,
				'creator' => $self->{'login_user'},
				'verbose_cb' => sub {
					my $message = shift;
					$env->{'psgi.errors'}->print(encode_utf8($message)."\n");
				},
			);
			my $competition = $self->backend->fetch_competition($self->{'page_id'});
			my $delete = Activity::Commons::Vote::Delete->new(%p);
			$delete->delete_competition_section_images($competition);
			my $load = Activity::Commons::Vote::Load->new(%p);
			# XXX recursive opts?
			$load->load($self->{'page_id'});

			# Redirect.
			$self->_redirect('/competition/'.$self->{'page_id'});
		}

	# Log record.
	} elsif ($self->{'page'} eq 'log') {
		if ($self->{'page_id'}) {
			$self->{'data'}->{'log'} = $self->backend->fetch_log($self->{'page_id'});
		}

	# Log list.
	} elsif ($self->{'page'} eq 'logs') {
		if ($self->{'page_id'}) {
			my @logs = $self->backend->fetch_logs({'competition_id' => $self->{'page_id'}});
			$self->{'data'}->{'logs'} = [];
			push @{$self->{'data'}->{'logs'}}, [
				'Date and time when log created',
				'Log type',
				'Log',
			], map {
				[
					$_->created_at->stringify,
					$_->log_type->type,
					Data::HTML::A->new(
						'data' => 'View log record',
						'url' => '/log/'.$_->id,
					),
				],
			} @logs;
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

		$self->{'_html_section_form'}->init(
			$self->{'data'}->{'section_form'},
			$self->{'data'}->{'competition'},
		);

	# Load theme form data.
	} elsif ($self->{'page'} eq 'theme_form') {
		if ($self->{'page_id'}) {
			$self->{'data'}->{'theme_form'}
				= $self->backend->fetch_theme($self->{'page_id'});
		}

	# Validate competition.
	} elsif ($self->{'page'} eq 'validate') {
		if ($self->{'page_id'}) {
			my %p = (
				'backend' => $self->backend,
				'creator' => $self->{'login_user'},
				'verbose_cb' => sub {
					my $message = shift;
					$env->{'psgi.errors'}->print(encode_utf8($message)."\n");
				},
			);
			my $validator = Activity::Commons::Vote::Validation->new(%p);
			$validator->validate($self->{'page_id'});

			# Redirect.
			$self->_redirect('/competition/'.$self->{'page_id'});
		}

	# Load validation data.
	} elsif ($self->{'page'} eq 'validation') {
		if ($self->{'page_id'}) {
			$self->{'data'}->{'validation'}
				= $self->backend->fetch_competition_validation($self->{'page_id'});
		}

	# Load validation form data.
	} elsif ($self->{'page'} eq 'validation_form') {
		$self->script_js([
			<<'END'
window.onload = function() {
	document.getElementById('validation_type_id').addEventListener("change", function() {
		var options = this.getElementsByTagName("option");
		var selected_id;
		for(var i=0; i<options.length; i++) {
			if (options[i].selected) {
				if (options[i].getAttribute('id') != null) {
					selected_id = options[i].getAttribute('id');
				}
			}
		}
		var url = "?competition_id="+document.getElementById('competition_id').value;
		if (selected_id) {
			url += '&validation_type_id='+selected_id;
		}
		window.location.href = url;
	});
};
END
		]);

		# TODO Check int for validation_type_id.
		my $validation_type_id = $req->parameters->{'validation_type_id'};

		# Update competition validation.
		if ($self->{'page_id'}) {
			$self->{'data'}->{'competition_validation'}
				= $self->backend->fetch_competition_validation($self->{'page_id'});
			$validation_type_id ||= $self->{'data'}->{'competition_validation'}->validation_type->id;
			$self->{'data'}->{'validation_types'} = [$self->backend->fetch_validation_types];
			# TODO Minus other validation types than mine.

		# Create competition validation.
		} else {
			my $competition_id = $req->parameters->{'competition_id'};
			if ($competition_id) {
				$self->{'data'}->{'competition'}
					= $self->backend->fetch_competition($competition_id);

				# Only not used in competition.
				$self->{'data'}->{'validation_types'}
					= [$self->backend->fetch_validation_types_not_used($competition_id)];

			} else {
				err "No competition id.";
			}
		}

		if ($validation_type_id) {
			$self->{'data'}->{'validation_type'} = $self->backend->fetch_validation_type({
				'validation_type_id' => $validation_type_id,
			});

			# Get options for validation type.
			$self->{'data'}->{'validation_type_options'}
				= [$self->backend->fetch_validation_type_options($validation_type_id)];
		}

		# TODO Optimize.
		$self->{'_html_competition_validation_form'}->init(
			$self->{'data'}->{'competition_validation'},
			$self->{'data'}->{'competition'},
			$self->{'data'}->{'validation_types'},
			$self->{'data'}->{'validation_type'},
			$self->{'data'}->{'validation_type_options'},
		);

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
		$self->{'_html_competition_form'}->process;

	# List of competitions page.
	} elsif ($self->{'page'} eq 'competitions') {
		$self->{'_html_competitions'}->process($self->{'data'}->{'competitions'});

	# View image.
	} elsif ($self->{'page'} eq 'image') {
		$self->{'_html_image'}->process($self->{'data'}->{'image'});

	# View images.
	} elsif ($self->{'page'} eq 'images') {
		$self->{'tags'}->put(
			['b', 'h1'],
			['d', $self->{'data'}->{'section'}->name],
			['e', 'h1'],
		);
		$self->{'_html_images'}->process($self->{'data'}->{'images'});
		$self->{'_html_pager'}->process($self->{'data'}->{'pager'});

	# Log record.
	} elsif ($self->{'page'} eq 'log') {
		# TODO Information about log.
		$self->{'_html_pre'}->process($self->{'data'}->{'log'}->log);

	# Log list.
	} elsif ($self->{'page'} eq 'logs') {
		$self->{'_html_table_view'}->process($self->{'data'}->{'logs'});

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
		$self->{'_html_section_form'}->process;

	# Theme form page.
	} elsif ($self->{'page'} eq 'theme_form') {
		$self->{'_html_theme_form'}->process(
			$self->{'data'}->{'theme_form'},
		);

	# Validation page.
	} elsif ($self->{'page'} eq 'validation') {
		$self->{'_html_competition_validation'}->process($self->{'data'}->{'validation'});

	# Validation form page.
	} elsif ($self->{'page'} eq 'validation_form') {
		$self->{'_html_competition_validation_form'}->process;

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
