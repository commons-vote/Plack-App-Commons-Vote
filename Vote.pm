package Plack::App::Commons::Vote;

use base qw(Plack::Component::Tags::HTML);
use strict;
use warnings;

use Activity::Commons::Vote::Delete;
use Activity::Commons::Vote::Import;
use Activity::Commons::Vote::Load;
use Activity::Commons::Vote::Stats;
use Activity::Commons::Vote::Validation;
use Commons::Link;
use Commons::Vote::Fetcher;
use Data::Commons::Vote::Competition;
use Data::Commons::Vote::CompetitionValidation;
use Data::Commons::Vote::CompetitionValidationOption;
use Data::Commons::Vote::CompetitionVoting;
use Data::Commons::Vote::Log;
use Data::Commons::Vote::PersonRole;
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
use Tags::HTML::Commons::Vote::CompetitionVoting;
use Tags::HTML::Commons::Vote::CompetitionVotingForm;
use Tags::HTML::Commons::Vote::Competitions;
use Tags::HTML::Commons::Vote::Main;
use Tags::HTML::Commons::Vote::Menu;
use Tags::HTML::Commons::Vote::Newcomers;
use Tags::HTML::Commons::Vote::PersonRole;
use Tags::HTML::Commons::Vote::PersonRoleForm;
use Tags::HTML::Commons::Vote::Section;
use Tags::HTML::Commons::Vote::SectionForm;
use Tags::HTML::Commons::Vote::ThemeForm;
use Tags::HTML::Commons::Vote::Vote;
use Tags::HTML::Commons::Vote::WikidataForm;
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

sub _cleanup {
	my $self = shift;

	if ($self->{'page'} eq 'vote_image') {
		$self->{'_html_vote'}->cleanup;
	}

	return;
}

sub _css {
	my $self = shift;

	$self->{'_html_menu'}->process_css;

	# Register page.
	if ($self->{'page'} eq 'register') {
		$self->{'_html_login_register'}->process_css;

	# Competition page.
	} elsif ($self->{'page'} eq 'competition') {
		$self->{'_html_competition'}->process_css;

	# View competition images.
	} elsif ($self->{'page'} eq 'competition_images') {
		$self->{'_html_pager'}->process_css;
		$self->{'_html_images'}->process_css;

	# Competition form page.
	} elsif ($self->{'page'} eq 'competition_form') {
		$self->{'_html_competition_form'}->process_css;

	# List of competition page.
	} elsif ($self->{'page'} eq 'competitions') {
		$self->{'_html_competitions'}->process_css;

	# View image.
	} elsif ($self->{'page'} eq 'image') {
		$self->{'_html_image'}->process_css;
		$self->{'_html_table_view'}->process_css;

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

	# Person role page.
	} elsif ($self->{'page'} eq 'role') {
		$self->{'_html_person_role'}->process_css;

	# Person role form page.
	} elsif ($self->{'page'} eq 'role_form') {
		$self->{'_html_person_role_form'}->process_css;

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

	# Validation report.
	} elsif ($self->{'page'} eq 'validation_report') {
		$self->{'_html_table_view'}->process_css;

	# Voting type page.
	} elsif ($self->{'page'} eq 'voting') {
		$self->{'_html_competition_voting'}->process_css;

	# Competition voting form page.
	} elsif ($self->{'page'} eq 'voting_form') {
		$self->{'_html_competition_voting_form'}->process_css;

	# Theme form page.
	} elsif ($self->{'page'} eq 'theme_form') {
		$self->{'_html_theme_form'}->process_css;

	# Voting image.
	} elsif ($self->{'page'} eq 'vote_image') {
		$self->{'_html_vote'}->process_css;

	# Voting grid.
	} elsif ($self->{'page'} eq 'vote_images') {
		if (exists $self->{'data'}->{'images'}) {
			$self->{'_html_pager'}->process_css;
			$self->{'_html_images_vote'}->process_css;
		}

	# Voting stats,
	} elsif ($self->{'page'} eq 'vote_stats') {
		$self->{'_html_table_view'}->process_css;

	# Wikidata form page.
	} elsif ($self->{'page'} eq 'wikidata_form') {
		$self->{'_html_wikidata_form'}->process_css;
	}

	return;
}

sub _check_access {
	my ($self, $cond_hr) = @_;

	if (exists $cond_hr->{'competition_id'} && $cond_hr->{'role_id'}) {
		my $count = $self->backend->count_person_role({
			'competition_id' => $cond_hr->{'competition_id'},
			'person_id' => $self->{'login_user'}->id,
			'role_id' => $cond_hr->{'role_id'},
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
	$self->{'_html_competition_voting'}
		= Tags::HTML::Commons::Vote::CompetitionVoting->new(%p);
	$self->{'_html_competition_voting_form'}
		= Tags::HTML::Commons::Vote::CompetitionVotingForm->new(
			%p,
			'form_link' => '/voting_save',
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
		'img_select_cb' => sub {
			my ($grid_self, $image) = @_;

			my $count = $self->backend->count_validation_bad({
				'competition_id' => $self->{'data'}->{'competition'}->id,
				'image_id' => $image->id,
			});

			return {
				'css_background_color' => $count ? 'red' : 'lightgreen',
				'value' => $count ? $count : decode_utf8('✓'),
			};
		},
		'img_src_cb' => sub {
			my $image = shift;
			return $self->{'_link'}->thumb_link($image->commons_name, $IMAGE_GRID_WIDTH);
		},
		'img_width' => $IMAGE_GRID_WIDTH,
	);
	$self->{'_html_images_vote'} = Tags::HTML::Image::Grid->new(
		%p,
		'img_link_cb' => sub {
			my $image = shift;
			return '/vote_image/'.$image->id.'?competition_voting_id='
				.$self->{'data'}->{'competition_voting'}->id;
		},
		'img_select_cb' => sub {
			my ($grid_self, $image) = @_;

			my $voting_type = $self->{'data'}->{'competition_voting'}->voting_type->type;
			my $person_id;
			if ($voting_type eq 'jury_voting' || $voting_type eq 'login_voting') {
				$person_id = $self->{'login_user'}->id;
			}
			my $vote = $self->backend->fetch_vote({
				'competition_voting_id' => $self->{'data'}->{'competition_voting'}->id,
				'image_id' => $image->id,
				defined $person_id ? ('person_id' => $person_id) : (),
			});
			if (defined $vote && defined $vote->vote_value) {
				my $vote_value;
				if (($voting_type eq 'jury_voting' || $voting_type eq 'login_voting')
					&& defined $self->{'data'}->{'competition_voting'}->number_of_votes) {

					$vote_value = $vote->vote_value;
				} else {
					$vote_value = decode_utf8('✓');
				}
				return {
					'css_background_color' => 'lightgreen',
					'value' => $vote_value,
				};
			} else {
				return {};
			}
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
	$self->{'_html_person_role'}
		= Tags::HTML::Commons::Vote::PersonRole->new(%p);
	$self->{'_html_person_role_form'}
		= Tags::HTML::Commons::Vote::PersonRoleForm->new(
			%p,
			'form_link' => '/role_save',
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
		'img_src_cb' => sub {
			my $image = shift;
			return $self->{'_link'}->thumb_link($image->commons_name, 1630);
		},
	);
	$self->{'_html_wikidata_form'}
		= Tags::HTML::Commons::Vote::WikidataForm->new(
			%p,
			'form_link' => '/import_competition',
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
			'required' => ['name',],
		};
		my $results = Data::FormValidator->check($parameters_hr, $profile_hr);
		if ($results->has_invalid) {
			err "Parameters are invalid.";
		}
		my $competition_id = $req->parameters->{'competition_id'} || undef;
		my $competition_to_update = Data::Commons::Vote::Competition->new(
			'created_by' => $self->{'login_user'},
			'id' => $competition_id,
			'logo' => decode_utf8($req->parameters->{'logo'}) || undef,
			'name' => decode_utf8($req->parameters->{'competition_name'}),
			'organizer' => decode_utf8($req->parameters->{'organizer'}) || undef,
			'organizer_logo' => decode_utf8($req->parameters->{'organizer_logo'}) || undef,
			'wd_qid' => $req->parameters->{'wd_qid'} || undef,
		);
		my $competition;
		my $competition_role = $self->backend->fetch_role({'name' => 'competition_admin'});
		if ($competition_id) {
			if ($self->_check_access({
					'competition_id' => $competition_id,
					'role_id' => $competition_role->id,
				})) {

				$competition = $self->backend->update_competition(
					$competition_id,
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
			$self->backend->save_person_role(Data::Commons::Vote::PersonRole->new(
				'competition' => $competition,
				'created_by' => $self->{'login_user'},
				'person' => $self->{'login_user'},
				'role' => $competition_role,
			));
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
		}

	# Import competition from Wikidata.
	} elsif ($self->{'page'} eq 'import_competition') {

		my $competition_qid = $req->parameters->{'competition_qid'};

		my $import = Activity::Commons::Vote::Import->new(
			'backend' => $self->backend,
			'creator' => $self->{'login_user'},
		);
		my $competition_id = $import->wd_competition($competition_qid);

		if ($competition_id) {
			$self->{'page'} = 'competition';
			$self->{'page_id'} = $competition_id;

			# Redirect.
			$self->_redirect('/competition/'.$competition_id);
		} else {
			$self->{'page'} = 'wikidata_form';
		}


	# Save role.
	} elsif ($self->{'page'} eq 'role_save') {
		my $parameters_hr = $req->parameters->as_hashref;
		my $profile_hr = {
			'required' => ['competition_id', 'wm_username', 'role_id'],
		};
		my $results = Data::FormValidator->check($parameters_hr, $profile_hr);
		if ($results->has_invalid) {
			err "Parameters are invalid.";
		}
		my $competition = $self->backend->fetch_competition({
			'competition_id' => $req->parameters->{'competition_id'},
		});
		if (! $competition) {
			err "Bad competition.";
		}
		my $wm_username = decode_utf8(ucfirst($req->parameters->{'wm_username'}));
		my $role_person = $self->backend->fetch_person({'wm_username' => $wm_username});
		my $role_id = $req->parameters->{'role_id'};
		my $role = $self->backend->fetch_role({'role_id' => $role_id});
		if (! defined $role) {
			err "Role doesn't exist.",
				'Role id', $role_id,
			;
		}
		# TODO Is role acceptable? If competition hasn't jury voting and want to add jury member?

		# Check if person hasn't this role in db.
		if (defined $role_person) {
			my $count = $self->backend->count_person_role({
				'person_id' => $role_person->id,
				'competition_id' => $competition->id,
				'role_id' => $role_id,
			});
			if ($count) {
				err "Username has this role.",
					'Wikimedia username', $wm_username,
					'Role', $role->description,
				;
			}

		# Create person in db.
		} else {
			my $user_id = $self->{'_fetcher'}->user_exists(decode_utf8($req->parameters->{'wm_username'}));
			if (! defined $user_id) {
				err "Username doesn't exists.",
					'Wikimedia username', $wm_username,
				;
			}
			$role_person = $self->backend->save_person(Data::Commons::Vote::Person->new(
				'wm_username' => $wm_username,
			));
		}
		my $person_role_to_update = Data::Commons::Vote::PersonRole->new(
			'competition' => $competition,
			'created_by' => $self->{'login_user'},
			'person' => $role_person,
			'role' => $role,
		);
		my $person_role = $self->backend->save_person_role($person_role_to_update);

		if (defined $person_role->id) {
			$self->{'page'} = 'role';
			$self->{'page_id'} = $competition->id;

			$self->_redirect('/competition/'.$competition->id);
		} else {
			$self->{'page'} = 'role_form';
		}

	# Save section.
	} elsif ($self->{'page'} eq 'section_save') {
		my $parameters_hr = $req->parameters->as_hashref;
		my $profile_hr = {
			'required' => ['competition_id', 'section_name',],
		};
		my $results = Data::FormValidator->check($parameters_hr, $profile_hr);
		if ($results->has_invalid) {
			err "Parameters are invalid.";
		}
		my $competition = $self->backend->fetch_competition({
			'competition_id' => $req->parameters->{'competition_id'},
		});
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
		$self->backend->schema->resultset('Competition')->search({
			'competition_id' => $competition->id,
		})->update({
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
			$self->{'page'} = 'competition';
			$self->{'page_id'} = $section->competition->id;

			# Redirect.
			$self->_redirect('/competition/'.$section->competition->id);
		} else {
			$self->{'page'} = 'section_form';
		}

	# Remove role.
	} elsif ($self->{'page'} eq 'role_remove') {
		if ($self->{'page_id'}) {
			my $person_role_id = $self->{'page_id'};
			my $person_role = $self->backend->fetch_person_role({
				'person_role_id' => $person_role_id,
			});
			if ($person_role->role->name eq 'competition_admin') {
				my $count_other = $self->backend->count_person_role({
					'competition_id' => $person_role->competition->id,
					'role_id' => $person_role->role->id,
				});
				if ($count_other > 1) {
					$self->backend->delete_person_role({
						'person_role_id' => $person_role_id,
					});
				} else {
					# XXX Error message to somewhere.
					#err "Cannot delete last role.";
				}
			} else {
				$self->backend->delete_person_role({
					'person_role_id' => $person_role_id,
				});
			}

			# Redirect.
			$self->_redirect('/competition/'.$person_role->competition->id);
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
			err "Parameters are invalid.";
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
		}

	# Remove validation.
	} elsif ($self->{'page'} eq 'validation_remove') {
		if ($self->{'page_id'}) {
			$self->backend->delete_competition_validation_options($self->{'page_id'});
			my $validation = $self->backend->delete_competition_validation($self->{'page_id'});

			# Delete validation results for this validation.
			$self->backend->delete_validation_bads({
				'competition_id' => $validation->competition->id,
				'validation_type_id' => $validation->validation_type->id,
			});

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
			err "Parameters are invalid.";
		}

		my $competition_id = $req->parameters->{'competition_id'};
		my $competition = $self->backend->fetch_competition({
			'competition_id' => $competition_id,
		});

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

	# Save voting type.
	} elsif ($self->{'page'} eq 'voting_save') {
		my $parameters_hr = $req->parameters->as_hashref;
		my $profile_hr = {
			'required' => ['competition_id', 'competition_voting_id', 'date_from', 'date_to'],
		};
		my $results = Data::FormValidator->check($parameters_hr, $profile_hr);
		if ($results->has_invalid) {
			err "Parameters are invalid.";
		}
		my $dt_from = $self->_date_from_params($req->parameters->{'date_from'});
		my $dt_to = $self->_date_from_params($req->parameters->{'date_to'});

		my $competition_id = $req->parameters->{'competition_id'};
		my $competition = $self->backend->fetch_competition({
			'competition_id' => $competition_id,
		});

		my $voting_type_id = $req->parameters->{'voting_type_id'};
		my $voting_type = $self->backend->fetch_voting_type({
			'voting_type_id' => $voting_type_id,
		});

		my $competition_voting = Data::Commons::Vote::CompetitionVoting->new(
			'competition' => $competition,
			'created_by' => $self->{'login_user'},
			'dt_from' => $dt_from,
			'dt_to' => $dt_to,
			'number_of_votes' => $req->parameters->{'number_of_votes'} || undef,
			'voting_type' => $voting_type,
		);
		$competition_voting = $self->backend->save_competition_voting($competition_voting);

		if ($competition_voting->id) {
			$self->{'page'} = 'competition';
			$self->{'page_id'} = $competition_voting->competition->id;

			# Redirect.
			$self->_redirect('/competition/'.$competition_voting->competition->id);
		} else {
			$self->{'page'} = 'voting_form';
		}

	# Remove voting type.
	} elsif ($self->{'page'} eq 'voting_remove') {
		if ($self->{'page_id'}) {
			my $competition_voting_id = $self->{'page_id'};
			my $competition_voting = $self->backend->delete_competition_voting($competition_voting_id);

			# Delete person roles for jury member.
			if ($competition_voting->voting_type->type eq 'jury_voting') {
				my $role = $self->backend->fetch_role({
					'name' => 'jury_member',
				});
				$self->backend->delete_person_role({
					'competition_id' => $competition_voting->competition->id,
					'role_id' => $role->id,
				});
			}

			# Redirect.
			$self->_redirect('/competition/'.$competition_voting->competition->id);
		}

	# Save vote.
	} elsif ($self->{'page'} eq 'vote_save') {
		my $competition_voting_id = $req->parameters->{'competition_voting_id'};
		my $count_competition_voting = $self->backend->count_competition_voting_by_now({
			'competition_voting_id' => $competition_voting_id,
		});
		my $image_id = $req->parameters->{'image_id'};
		my $count_image = $self->backend->count_image($image_id);
		if ($count_image && $count_competition_voting) {
			my $competition_voting = $self->backend->fetch_competition_voting({
				'competition_voting_id' => $competition_voting_id,
			});
			my $next_image = $req->parameters->{'next_image'};

			# Move to next image.
			my $next_image_id = $req->parameters->{'next_image_id'};
			if ($next_image eq 'Next image') {

				# Redirect.
				$self->_redirect('/vote_image/'.$next_image_id.'?competition_voting_id='.$competition_voting->id);

			# Save vote.
			} else {
				my $voting_type = $competition_voting->voting_type->type;

				# Check access.
				my $access = 0;
				if ($voting_type eq 'jury_voting') {
					my $jury_role = $self->backend->fetch_role({'name' => 'jury_member'});
					if ($self->_check_access({
							'competition_id' => $competition_voting->competition->id,
							'role_id' => $jury_role->id,
						})) {

						$access = 1;
					}
				} else {
					$access = 1;
				}
				if ($access) {

					my $person;
					if ($voting_type eq 'jury_voting' || $voting_type eq 'login_voting') {
						$person = $self->{'login_user'};
					}

					# Check voting.
					my $count_vote = $self->backend->count_vote({
						'competition_voting_id' => $competition_voting_id,
						'image_id' => $image_id,
						defined $person ? ('person_id' => $person->id) : (),
					});

					# Vote exists.
					my $vote_value = $req->parameters->{'vote_value'};
					if ($count_vote
						# Update voting 0 .. X.
						&& ($voting_type eq 'jury_voting' || $voting_type eq 'login_voting')) {

						$self->backend->delete_vote({
							'competition_voting_id' => $competition_voting_id,
							'image_id' => $image_id,
							'person_id' => $person->id,
						});
					}

					# Save new anonymous vote.
					if (($voting_type eq 'anonymous_voting' && ! $count_vote)
						# Save yes/no voting.
						|| (($voting_type eq 'jury_voting' || $voting_type eq 'login_voting')
						&& $vote_value ne '')) {

						my $image = $self->backend->fetch_image($image_id);
						$self->backend->save_vote(Data::Commons::Vote::Vote->new(
							'competition_voting' => $competition_voting,
							'image' => $image,
							defined $person ? ('person' => $person) : (),
							'vote_value' => $vote_value,
						));
					}
				}

				if ($competition_voting->id) {
					$self->{'page'} = 'vote_images';
					$self->{'page_id'} = $competition_voting->id;

					# Redirect.
					if (defined $next_image_id) {
						$self->_redirect('/vote_image/'.$next_image_id.'?competition_voting_id='.$competition_voting->id);
					} else {
						$self->_redirect('/vote_images/'.$competition_voting->id);
					}
				} else {
					$self->{'page'} = 'vote_image';
				}
			}
		}
	}

	# Main page.
	if ($self->{'page'} eq 'main') {
		$self->{'section'} = $self->{'_html_main'}->{'text'}->{'eng'}->{'my_competitions'};

		# My competitions.
		my $competition_role = $self->backend->fetch_role({'name' => 'competition_admin'});
		$self->{'data'}->{'competitions'}
			= [$self->backend->fetch_competitions({
				'person_roles.person_id' => $self->{'login_user'}->id,
				'person_roles.role_id' => $competition_role->id,
			}, {
				'join' => 'person_roles',
			})];

		# All my competition votings for statistics.
		$self->{'data'}->{'competition_votings_stats'} = {};
		for my $competition (@{$self->{'data'}->{'competitions'}}) {
			my @competition_votings = $self->backend->fetch_competition_votings({
				'competition_id' => $competition->id,
			});
			$self->{'data'}->{'competition_votings_stats'}->{$competition->id} ||= [];
			push @{$self->{'data'}->{'competition_votings_stats'}->{$competition->id}}, @competition_votings;
		};

		# Competition in which i am member of jury
		my $jury_role = $self->backend->fetch_role({'name' => 'jury_member'});
		my @person_roles = $self->backend->fetch_person_roles({
			'person_id' => $self->{'login_user'}->id,
			'role_id' => $jury_role->id,
		});
		$self->{'data'}->{'competition_votings_jury'} = [];
		my $dtf = $self->backend->schema->storage->datetime_parser;
		my $jury_voting_type = $self->backend->fetch_voting_type({'type' => 'jury_voting'});
		foreach my $person_role (@person_roles) {
			my $competition_voting = $self->backend->fetch_competition_voting({
				'me.competition_id' => $person_role->competition->id,
				'date_from' => {'<=' => $dtf->format_datetime(DateTime->now)},
				'date_to' => {'>' => $dtf->format_datetime(DateTime->now)},
				'competition.images_loaded_at' => {'!=' => undef},
				'voting_type_id' => $jury_voting_type->id,
			}, {
				'join' => 'competition',
			});
			if (defined $competition_voting) {
				push @{$self->{'data'}->{'competition_votings_jury'}}, $competition_voting;
			}
		}

		# Other competitions.
		my $login_voting_type = $self->backend->fetch_voting_type({'type' => 'login_voting'});
		$self->{'data'}->{'competition_votings_login'}
			= [$self->backend->fetch_competition_votings({
				'date_from' => {'<=' => $dtf->format_datetime(DateTime->now)},
				'date_to' => {'>' => $dtf->format_datetime(DateTime->now)},
				'competition.images_loaded_at' => {'!=' => undef},
				'voting_type_id' => $login_voting_type->id,
			}, {
				'join' => 'competition',
			})];

	# Load competition data.
	} elsif ($self->{'page'} eq 'competition') {
		if ($self->{'page_id'}) {
			my $competition_id = $self->{'page_id'};
			my $competition_role = $self->backend->fetch_role({'name' => 'competition_admin'});
			if ($self->_check_access({
					'competition_id' => $competition_id,
					'role_id' => $competition_role->id,
				})) {

				$self->{'data'}->{'competition'}
					= $self->backend->fetch_competition({
						'competition_id' => $competition_id,
					}, {}, {
						'person_roles' => 1,
						'sections' => 1,
						'validations' => 1,
						'votings' => 1,
					});
			}
		}

	# Load competition form data.
	} elsif ($self->{'page'} eq 'competition_form') {
		if ($self->{'page_id'}) {
			my $competition_role = $self->backend->fetch_role({'name' => 'competition_admin'});
			if ($self->_check_access({
					'competition_id' => $self->{'page_id'},
					'role_id' => $competition_role->id,
				})) {

				$self->{'data'}->{'competition_form'}
					= $self->backend->fetch_competition({
					'competition_id' => $self->{'page_id'},
				});
			}
		}
		$self->{'_html_competition_form'}->init(
			$self->{'data'}->{'competition_form'},
		);

	# View competition images.
	} elsif ($self->{'page'} eq 'competition_images') {

		# Competition id.
		if ($self->{'page_id'}) {

			# Get information about competition.
			$self->{'data'}->{'competition'} = $self->backend->fetch_competition({
				'competition_id' => $self->{'page_id'},
			});

			# URL parameters.
			my $page_num = $req->parameters->{'page_num'} || 1;

			# Count images.
			$self->{'data'}->{'images_count'}
				= $self->backend->count_competition_images($self->{'page_id'});
			my $pages = pages_num($self->{'data'}->{'images_count'}, $IMAGES_ON_PAGE);
			my $actual_page = adjust_actual_page($page_num, $pages);
			my ($begin_index) = compute_index_values($self->{'data'}->{'images_count'},
				$actual_page, $IMAGES_ON_PAGE);

			# Fetch selected images.
			$self->{'data'}->{'images'} = [$self->backend->fetch_competition_images($self->{'page_id'}, {
				'offset' => $begin_index,
				'rows' => $IMAGES_ON_PAGE,
			})];

			# Pager.
			$self->{'data'}->{'pager'} = {
				'actual_page' => $actual_page,
				'pages_num' => $pages,
			};
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

			my $license;
			if (defined $self->{'data'}->{'image'}->license_obj
				&& defined $self->{'data'}->{'image'}->license_obj->text) {

				$license = $self->{'data'}->{'image'}->license_obj->text;
			} elsif ($self->{'data'}->{'image'}->license) {
				$license = $self->{'data'}->{'image'}->license
			}

			push @{$self->{'data'}->{'image_metadata'}}, [
				'Information',
				'Value',
			], [
				'Wikimedia username',
				[
					['b', 'a'],
					['a', 'href', $self->{'_link'}->mw_user_link($self->{'data'}->{'image'}->uploader->wm_username)],
					['d', $self->{'data'}->{'image'}->uploader->wm_username],
					['e', 'a'],
				],
			], [
				'Comment',
				$self->{'data'}->{'image'}->comment,
			],
			defined $license ? ([
				'License',
				$self->{'data'}->{'image'}->license_obj->text,
			]) : (), [
				'Dimensions',
				$self->{'data'}->{'image'}->width.'x'.$self->{'data'}->{'image'}->height,
			], [
				'Size',
				$self->{'data'}->{'image'}->size,
			], [
				'Created',
				$self->{'data'}->{'image'}->dt_created->stringify,
			], [
				'Uploaded',
				$self->{'data'}->{'image'}->dt_uploaded->stringify,
			], [
				'Image on Wikimedia Commons',
				[
					['b', 'a'],
					['a', 'href', $self->{'_link'}->mw_file_link($self->{'data'}->{'image'}->commons_name)],
					['d', $self->{'data'}->{'image'}->commons_name],
					['e', 'a'],
				],
			];
		}

	# View images.
	} elsif ($self->{'page'} eq 'images') {

		# Section id.
		if ($self->{'page_id'}) {

			# Get information about section.
			$self->{'data'}->{'section'} = $self->backend->fetch_section($self->{'page_id'});

			$self->{'data'}->{'competition'} = $self->{'data'}->{'section'}->competition;

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
			my $competition = $self->backend->fetch_competition({
				'competition_id' => $self->{'page_id'},
			});
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

	# Validation report.
	} elsif ($self->{'page'} eq 'validation_report') {
		if ($self->{'page_id'}) {
			my @bad_validations = $self->backend->{'schema'}->resultset('ValidationBad')->search({
				'competition_id' => $self->{'page_id'},
			}, {
				group_by => [ 'me.image_id' ],
#				order_by => { -desc => 'validation_count' },
#				select => [ 'image.image', { count => 'image_id' -as => 'validation_count' } ],
#				select => [ 'image.image' ],
				select => [ 'me.image_id' ],
			});
			$self->{'data'}->{'validation_report'} = [];
			push @{$self->{'data'}->{'validation_report'}}, [
				'Image',
				'Image information',
				'Validations',
			];
			foreach my $image_db (@bad_validations) {
				my $image = $image_db->image;
				my @image_validations = $self->backend->{'schema'}->resultset('ValidationBad')->search({
					'image_id' => $image->image_id,
				});
				my @validations;
				foreach my $image_validation (@image_validations) {
					if (@validations) {
						push @validations, (
							['b', 'br'],
							['e', 'br'],
						);
					}
					push @validations, (
						['d', $image_validation->validation_type->description],
					);
				}
				my @image_info = (
					['d', $image->width.'x'.$image->height],
					['b', 'br'],
					['e', 'br'],
					['d', 'size: '.$image->size],
					['b', 'br'],
					['e', 'br'],
					['d', 'author: '],
					['b', 'a'],
					['a', 'href', $self->{'_link'}->mw_user_link($image->uploader->wm_username)],
					['d', $image->uploader->wm_username],
					['e', 'a'],
				);
				push @{$self->{'data'}->{'validation_report'}}, [
					Data::HTML::A->new(
						'data' => $image->image,
						'url' => $self->{'_link'}->mw_file_link($image->image),
					),
					\@image_info,
					\@validations,
				];
			}
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

	# Load person role data.
	} elsif ($self->{'page'} eq 'role') {
		if ($self->{'page_id'}) {
			$self->{'data'}->{'person_role'}
				= $self->backend->fetch_person_role({
					'person_role_id' => $self->{'page_id'},
				});
		}

	# Load person role form data.
	} elsif ($self->{'page'} eq 'role_form') {

		# Update person role.
		if ($self->{'page_id'}) {
			$self->{'data'}->{'person_role'}
				= $self->backend->fetch_person_role($self->{'page_id'});

		# Create person role.
		} else {
			my $competition_id = $req->parameters->{'competition_id'};
			if ($competition_id) {
				$self->{'data'}->{'competition'}
					= $self->backend->fetch_competition({
					'competition_id' => $competition_id,
				});
			} else {
				err "No competition id.";
			}
		}

		$self->{'data'}->{'roles'} = [];
		push @{$self->{'data'}->{'roles'}}, $self->backend->fetch_role({'name' => 'competition_admin'});
		my $jury_count = $self->backend->count_competition_voting_by_now({
			'competition_id' => $self->{'data'}->{'competition'}->id,
		});
		if ($jury_count) {
			push @{$self->{'data'}->{'roles'}}, $self->backend->fetch_role({'name' => 'jury_member'});
		}

		# XXX Optimize.
		$self->{'_html_person_role_form'}->init(
			$self->{'data'}->{'person_role'},
			$self->{'data'}->{'roles'},
			$self->{'data'}->{'competition'},
		);

	# Load section data.
	} elsif ($self->{'page'} eq 'section') {
		if ($self->{'page_id'}) {
			$self->{'data'}->{'section'}
				= $self->backend->fetch_section($self->{'page_id'});
		}

	# Load section form data.
	} elsif ($self->{'page'} eq 'section_form') {
		if ($self->{'page_id'}) {
			my $section_id = $self->{'page_id'};
			$self->{'data'}->{'section_form'}
				= $self->backend->fetch_section($section_id);
		} else {
			my $competition_id = $req->parameters->{'competition_id'};
			if ($competition_id) {
				$self->{'data'}->{'competition'}
					= $self->backend->fetch_competition({
					'competition_id' => $competition_id,
				});
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
		$self->{'_html_theme_form'}->init($self->{'data'}->{'theme_form'});

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
			$self->_redirect('/competition_images/'.$self->{'page_id'});
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
					= $self->backend->fetch_competition({
					'competition_id' => $competition_id,
				});

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

	# Load competition voting data.
	} elsif ($self->{'page'} eq 'voting') {
		if ($self->{'page_id'}) {
			my $competition_voting_id = $self->{'page_id'};
			$self->{'data'}->{'voting_type'}
				= $self->backend->fetch_competition_voting({
					'competition_voting_id' => $competition_voting_id,
				});
		}

	# Competition voting form page.
	} elsif ($self->{'page'} eq 'voting_form') {

		# Update competition voting.
		if ($self->{'page_id'}) {
			my $competition_voting_id = $self->{'page_id'};
			$self->{'data'}->{'competition_voting'}
				= $self->backend->fetch_competition_voting({
					'competition_voting_id' => $competition_voting_id,
				});
			$self->{'data'}->{'voting_types'} = [$self->backend->fetch_voting_types];
			# TODO Minus other voting types than mine.

		# Create competition voting.
		} else {
			my $competition_id = $req->parameters->{'competition_id'};
			if ($competition_id) {
				$self->{'data'}->{'competition'}
					= $self->backend->fetch_competition({
					'competition_id' => $competition_id,
				});

				# Only not used in competition.
				$self->{'data'}->{'voting_types'}
					= [$self->backend->fetch_voting_types_not_used($competition_id)];

			} else {
				err "No competition id.";
			}
		}

		$self->{'_html_competition_voting_form'}->init(
			$self->{'data'}->{'competition_voting'},
			$self->{'data'}->{'voting_types'},
			$self->{'data'}->{'competition'},
		);

	# Voting image.
	} elsif ($self->{'page'} eq 'vote_image') {
		if ($self->{'page_id'}) {
			my $image_id = $self->{'page_id'};
			my $count_image = $self->backend->count_image($image_id);
			my $competition_voting_id = $req->parameters->{'competition_voting_id'};
			my $count_competition_voting = $self->backend->count_competition_voting_by_now({
				'competition_voting_id' => $competition_voting_id,
			});
			if ($count_image && $count_competition_voting) {
				$self->{'data'}->{'competition_voting'}
					= $self->backend->fetch_competition_voting({
						'competition_voting_id' => $competition_voting_id,
					});
				my $voting_type = $self->{'data'}->{'competition_voting'}->voting_type->type;
				my $jury_role = $self->backend->fetch_role({'name' => 'jury_member'});
				my $access = 0;
				if ($voting_type eq 'jury_voting' && $self->_check_access({
						'competition_id' => $self->{'data'}->{'competition_voting'}->competition->id,
						'role_id' => $jury_role->id,
					})) {
					$access = 1;
				};
				if ($voting_type ne 'jury_voting') {
					$access = 1;
				}
				if ($access) {
					my $person_id;
					my $person;
					if ($voting_type eq 'jury_voting' || $voting_type eq 'login_voting') {
						$person_id = $self->{'login_user'}->id;
						$person = $self->{'login_user'};
					}
					$self->{'data'}->{'vote'} = $self->backend->fetch_vote({
						'competition_voting_id' => $competition_voting_id,
						'image_id' => $image_id,
						'person_id' => $person_id,
					});
					if (! defined $self->{'data'}->{'vote'}) {
						$self->{'data'}->{'vote'} = Data::Commons::Vote::Vote->new(
							'competition_voting' => $self->{'data'}->{'competition_voting'},
							'image' => $self->backend->fetch_image($image_id),
							'person' => $person,
						);
					}

					# Next image id.
					my $next_image = $self->backend->fetch_image_next($image_id);
					if (defined $next_image) {
						$self->{'data'}->{'next_image_id'} = $next_image->id;
					}
				}
			}
		}
		my $remote_addr = $req->env->{'HTTP_X_REAL_IP'} || $req->env->{'REMOTE_ADDR'};
		$self->{'_html_vote'}->init($self->{'data'}->{'vote'}, $remote_addr, $self->{'data'}->{'next_image_id'});

	# Voting grid.
	} elsif ($self->{'page'} eq 'vote_images') {
		if (defined $self->{'page_id'}) {
			my $competition_voting_id = $self->{'page_id'};
			my $count_competition_voting = $self->backend->count_competition_voting_by_now({
				'competition_voting_id' => $competition_voting_id,
			});
			if ($count_competition_voting) {
				$self->{'data'}->{'competition_voting'}
					= $self->backend->fetch_competition_voting({
						'competition_voting_id' => $competition_voting_id,
					});
				my $voting_type = $self->{'data'}->{'competition_voting'}->voting_type->type;
				my $jury_role = $self->backend->fetch_role({'name' => 'jury_member'});
				my $access = 0;
				if ($voting_type eq 'jury_voting' && $self->_check_access({
						'competition_id' => $self->{'data'}->{'competition_voting'}->competition->id,
						'role_id' => $jury_role->id,
					})) {
					$access = 1;
				};
				if ($voting_type ne 'jury_voting') {
					$access = 1;
				}
				if ($access) {

					# Get information about competition.
					my $competition_id = $self->{'data'}->{'competition_voting'}->competition->id;
					$self->{'data'}->{'competition'} = $self->backend->fetch_competition({
						'competition_id' => $competition_id,
					});

					# URL parameters.
					my $page_num = $req->parameters->{'page_num'} || 1;

					# Count images.
					$self->{'data'}->{'images_count'}
						= $self->backend->count_competition_images_valid($competition_id);
					my $pages = pages_num($self->{'data'}->{'images_count'}, $IMAGES_ON_PAGE);
					my $actual_page = adjust_actual_page($page_num, $pages);
					my ($begin_index) = compute_index_values($self->{'data'}->{'images_count'},
						$actual_page, $IMAGES_ON_PAGE);

					# Fetch selected images.
					$self->{'data'}->{'images'} = [
						$self->backend->fetch_competition_images_valid(
							$competition_id, {
								'offset' => $begin_index,
								'rows' => $IMAGES_ON_PAGE,
							},
						),
					];

					# Pager.
					$self->{'data'}->{'pager'} = {
						'actual_page' => $actual_page,
						'pages_num' => $pages,
					};
				}
			}
		}

	# Voting stats,
	} elsif ($self->{'page'} eq 'vote_stats') {
		if (defined $self->{'page_id'}) {
			my $competition_voting_id = $self->{'page_id'};

			my $count_competition_voting = $self->backend->count_competition_voting({
				'competition_voting_id' => $competition_voting_id,
			});
			if ($count_competition_voting) {
				my $competition_voting = $self->backend->fetch_competition_voting({
						'competition_voting_id' => $competition_voting_id,
					});
				$self->{'data'}->{'competition_voting'} = $competition_voting;
				my $competition_role = $self->backend->fetch_role({'name' => 'competition_admin'});
				if ($self->_check_access({
						'competition_id' => $competition_voting->competition->id,
						'role_id' => $competition_role->id,
					})) {

					$self->{'data'}->{'vote_stats'} = [];
					push @{$self->{'data'}->{'vote_stats'}}, [
						'Image',
						'Wikimedia username',
						'Count of votes',
						'Sum of votes',
					];
					foreach my $vote_stat ($self->backend->fetch_vote_counted($competition_voting_id)) {
						push @{$self->{'data'}->{'vote_stats'}}, [
							$vote_stat->image->commons_name,
							$vote_stat->image->uploader->wm_username,
							$vote_stat->vote_count,
							$vote_stat->vote_sum,
						];
					}
				} else {
					$self->{'data'}->{'no_access'} = 1;
				}
			}
		}

	# Wikidata form.
	} elsif ($self->{'page'} eq 'wikidata_form') {
		$self->{'_html_wikidata_form'}->init;

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

	# View competition images.
	} elsif ($self->{'page'} eq 'competition_images') {
		$self->{'tags'}->put(
			['b', 'h1'],
			['d', $self->{'data'}->{'competition'}->name],
			['b', 'a'],
			['a', 'href', '/validation_report/'.$self->{'page_id'}],
			['d', '(validation report)'],
			['e', 'a'],
			['e', 'h1'],
		);
		$self->{'_html_images'}->process($self->{'data'}->{'images'});
		$self->{'_html_pager'}->process($self->{'data'}->{'pager'});

	# List of competitions page.
	} elsif ($self->{'page'} eq 'competitions') {
		$self->{'_html_competitions'}->process($self->{'data'}->{'competitions'});

	# View image.
	} elsif ($self->{'page'} eq 'image') {
		$self->{'_html_image'}->process($self->{'data'}->{'image'});
		$self->{'_html_table_view'}->process($self->{'data'}->{'image_metadata'});

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
		$self->{'_html_main'}->process(
			$self->{'data'}->{'competitions'},
			$self->{'data'}->{'competition_votings_stats'},
			$self->{'data'}->{'competition_votings_jury'},
			$self->{'data'}->{'competition_votings_login'},
		);

	# List of newcomers.
	} elsif ($self->{'page'} eq 'newcomers') {
		$self->{'_html_newcomers'}->process($self->{'data'}->{'newcomers'});

	# Person role page.
	} elsif ($self->{'page'} eq 'role') {
		$self->{'_html_person_role'}->process($self->{'data'}->{'person_role'});

	# Person role form page.
	} elsif ($self->{'page'} eq 'role_form') {
		$self->{'_html_person_role_form'}->process;

	# Section page.
	} elsif ($self->{'page'} eq 'section') {
		$self->{'_html_section'}->process($self->{'data'}->{'section'});

	# Section form page.
	} elsif ($self->{'page'} eq 'section_form') {
		$self->{'_html_section_form'}->process;

	# Theme form page.
	} elsif ($self->{'page'} eq 'theme_form') {
		$self->{'_html_theme_form'}->process;

	# Validation page.
	} elsif ($self->{'page'} eq 'validation') {
		$self->{'_html_competition_validation'}->process($self->{'data'}->{'validation'});

	# Validation form page.
	} elsif ($self->{'page'} eq 'validation_form') {
		$self->{'_html_competition_validation_form'}->process;

	# Validation report.
	} elsif ($self->{'page'} eq 'validation_report') {
		$self->{'_html_table_view'}->process($self->{'data'}->{'validation_report'});

	# Voting type page.
	} elsif ($self->{'page'} eq 'voting') {
		$self->{'_html_competition_voting'}->process($self->{'data'}->{'voting_type'});

	# Competition voting form page.
	} elsif ($self->{'page'} eq 'voting_form') {
		$self->{'_html_competition_voting_form'}->process;

	# Voting image.
	} elsif ($self->{'page'} eq 'vote_image') {
		$self->{'_html_vote'}->process;

	# Voting grid.
	} elsif ($self->{'page'} eq 'vote_images') {
		if (exists $self->{'data'}->{'images'}) {
			$self->{'tags'}->put(
				['b', 'h1'],
				['d', $self->{'data'}->{'competition'}->name
					.' - '.$self->{'data'}->{'competition_voting'}->voting_type->description],
				['e', 'h1'],
			);
			$self->{'_html_images_vote'}->process($self->{'data'}->{'images'});
			$self->{'_html_pager'}->process($self->{'data'}->{'pager'});
		} else {
			$self->{'tags'}->put(
				['d', 'No images.'],
			);
		}

	# Voting stats,
	} elsif ($self->{'page'} eq 'vote_stats') {
		if ($self->{'data'}->{'no_access'}) {
			$self->{'tags'}->put(
				['d', "Competition doesn't exist."],
			);
		} else {
			$self->{'tags'}->put(
				['b', 'h1'],
				['d', $self->{'data'}->{'competition_voting'}->competition->name
					.' - '.$self->{'data'}->{'competition_voting'}->voting_type->description],
				['e', 'h1'],
			);
			$self->{'_html_table_view'}->process($self->{'data'}->{'vote_stats'});
		}

	# Wikidata form page.
	} elsif ($self->{'page'} eq 'wikidata_form') {
		$self->{'_html_wikidata_form'}->process;

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
